{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE TypeOperators       #-}
{-# LANGUAGE TypeFamilies #-}

module Data.Conduit.Process.Effectful
  ( sourceProcessWithStreams
  ) where

import           Control.Monad.Trans                (lift)
import           Data.ByteString                    (ByteString)
import qualified Data.ByteString                    as BS (null)
import           Data.ByteString.Builder.Extra      (defaultChunkSize)
import           Data.Conduit                       (ConduitT, awaitForever,
                                                     runConduit, yield, (.|))
import           Data.Functor                       (($>))
import           Data.Streaming.Process.Effectful   (InputSource, OutputSink,
                                                     StreamingProcessHandle,
                                                     isStdStream, osStdStream,
                                                     streamingProcess,
                                                     streamingProcessHandleRaw,
                                                     waitForStreamingProcess)
import           Data.Void                          (Void)
import           Effectful                          (Eff, 
                                                     Limit (Unlimited),
                                                     Persistence (Ephemeral),
                                                     UnliftStrategy (ConcUnlift),
                                                     liftIO, withEffToIO, (:>))
import           Effectful.Concurrent               (Concurrent)
import           Effectful.Concurrent.Async         (Concurrently (..),
                                                     runConcurrently)
import           Effectful.Exception                (finally, onException)
import           Effectful.FileSystem               (FileSystem)
import           Effectful.FileSystem.IO            (BufferMode (NoBuffering),
                                                     Handle, hClose,
                                                     hSetBuffering)
import           Effectful.FileSystem.IO.ByteString (hGetSome, hPut)
import           Effectful.Process                  (CreateProcess, Process,
                                                     StdStream (CreatePipe),
                                                     terminateProcess)
import           System.Exit                        (ExitCode)

instance (FileSystem :> es) => InputSource (ConduitT ByteString o (Eff es) ()) where
  isStdStream =
    (\(Just h) -> hSetBuffering h NoBuffering $> sinkHandle h, Just CreatePipe)

instance (FileSystem :> es, r ~ (), r' ~ ()) =>
         InputSource (ConduitT ByteString o (Eff es) r, Eff es r') where
  isStdStream =
    ( \(Just h) -> hSetBuffering h NoBuffering $> (sinkHandle h, hClose h)
    , Just CreatePipe)

instance (FileSystem :> es) => OutputSink (ConduitT i ByteString (Eff es) ()) where
  osStdStream =
    ( \(Just h) -> hSetBuffering h NoBuffering $> sourceHandle h
    , Just CreatePipe)

instance (FileSystem :> es, r ~ (), r' ~ ()) =>
         OutputSink (ConduitT i ByteString (Eff es) r, Eff es r') where
  osStdStream =
    ( \(Just h) -> hSetBuffering h NoBuffering $> (sourceHandle h, hClose h)
    , Just CreatePipe)

sinkHandle :: (FileSystem :> es) => Handle -> ConduitT ByteString o (Eff es) ()
sinkHandle h = awaitForever (lift . hPut h)

sourceHandle ::
     (FileSystem :> es) => Handle -> ConduitT i ByteString (Eff es) ()
sourceHandle h = do
  bs <- lift $ hGetSome h defaultChunkSize
  if BS.null bs
    then pure ()
    else yield bs >> sourceHandle h

sourceProcessWithStreams ::
     (Process :> es, Concurrent :> es, FileSystem :> es)
  => CreateProcess
  -> ConduitT () ByteString (Eff es) ()
  -> ConduitT ByteString Void (Eff es) a
  -> ConduitT ByteString Void (Eff es) b
  -> Eff es (ExitCode, a, b)
sourceProcessWithStreams cp producerStdin consumerStdout consumerStderr = do
  ((sinkStdin, closeStdin), (sourceStdout, closeStdout), (sourceStderr, closeStderr), sph) <-
    streamingProcess cp
  (_, resStdout, resStderr) <-
    runConcurrently
      ((,,)
         <$> Concurrently
               (runConduit (producerStdin .| sinkStdin) `finally` closeStdin)
         <*> Concurrently (runConduit (sourceStdout .| consumerStdout))
         <*> Concurrently
               (runConduit (sourceStderr .| consumerStderr)
                  `finally` (closeStdout >> closeStderr)))
      `onException` terminateStreamingProcess sph
  ec <- waitForStreamingProcess sph
  return (ec, resStdout, resStderr)

terminateStreamingProcess ::
     (Process :> es) => StreamingProcessHandle es -> Eff es ()
terminateStreamingProcess = terminateProcess . streamingProcessHandleRaw

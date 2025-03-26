{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeOperators    #-}

module Data.Conduit.Process.Effectful
  ( sourceProcessWithStreams
  ) where

import           Data.ByteString            (ByteString)
import           Data.Conduit               (ConduitT, runConduit, (.|))
import           Data.Conduit.Process       (StreamingProcessHandle,
                                             streamingProcess,
                                             streamingProcessHandleRaw,
                                             waitForStreamingProcess)
import           Data.Void                  (Void)
import           Effectful                  (Eff, IOE, Limit (Unlimited),
                                             Persistence (Ephemeral),
                                             UnliftStrategy (ConcUnlift),
                                             liftIO, withEffToIO, (:>))
import           Effectful.Concurrent.Async (Concurrent, Concurrently (..),
                                             runConcurrently)
import           Effectful.Exception        (finally, onException)
import           Effectful.Process          (CreateProcess, Process,
                                             terminateProcess)
import           System.Exit                (ExitCode)

sourceProcessWithStreams ::
     (Process :> es, Concurrent :> es, IOE :> es)
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
     (Process :> es) => StreamingProcessHandle -> Eff es ()
terminateStreamingProcess = terminateProcess . streamingProcessHandleRaw

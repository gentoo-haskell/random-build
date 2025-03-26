{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeOperators    #-}

module Data.Conduit.Process.Effectful
  ( sourceProcessWithStreams
  ) where

import           Control.Concurrent.Async (Concurrently (..), runConcurrently)
import           Control.Exception        (finally, onException)
import           Data.ByteString          (ByteString)
import           Data.Conduit             (ConduitT, runConduit, (.|))
import           Data.Conduit.Process     (StreamingProcessHandle,
                                           streamingProcess,
                                           streamingProcessHandleRaw,
                                           waitForStreamingProcess)
import           Data.Void                (Void)
import           Effectful                (Eff, IOE, Limit (Unlimited),
                                           Persistence (Ephemeral),
                                           UnliftStrategy (ConcUnlift),
                                           withEffToIO, (:>))
import           System.Exit              (ExitCode)
import           System.Process           (CreateProcess, terminateProcess)

sourceProcessWithStreams ::
     (IOE :> es)
  => CreateProcess
  -> ConduitT () ByteString (Eff es) ()
  -> ConduitT ByteString Void (Eff es) a
  -> ConduitT ByteString Void (Eff es) b
  -> Eff es (ExitCode, a, b)
sourceProcessWithStreams cp producerStdin consumerStdout consumerStderr =
  withEffToIO (ConcUnlift Ephemeral Unlimited) $ \u -> do
    ((sinkStdin, closeStdin), (sourceStdout, closeStdout), (sourceStderr, closeStderr), sph) <-
      streamingProcess cp
    (_, resStdout, resStderr) <-
      runConcurrently
        ((,,)
           <$> Concurrently
                 (u (runConduit $ producerStdin .| sinkStdin)
                    `finally` closeStdin)
           <*> Concurrently (u $ runConduit $ sourceStdout .| consumerStdout)
           <*> Concurrently (u $ runConduit $ sourceStderr .| consumerStderr))
        `finally` (closeStdout >> closeStderr)
        `onException` terminateStreamingProcess sph
    ec <- waitForStreamingProcess sph
    return (ec, resStdout, resStderr)

terminateStreamingProcess :: StreamingProcessHandle -> IO ()
terminateStreamingProcess = terminateProcess . streamingProcessHandleRaw

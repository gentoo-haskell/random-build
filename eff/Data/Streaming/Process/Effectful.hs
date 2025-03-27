{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeOperators    #-}

module Data.Streaming.Process.Effectful
  ( StreamingProcessHandle
  , streamingProcess
  , streamingProcessHandleRaw
  , waitForStreamingProcess
  , InputSource
  , isStdStream
  , OutputSink
  , osStdStream
  ) where

import           Control.Exception        (throw)
import           Data.Maybe               (fromMaybe)
import           Effectful                (Eff, (:>))
import           Effectful.Concurrent     (Concurrent, forkIOWithUnmask)
import           Effectful.Concurrent.STM (STM, TMVar, atomically,
                                           newEmptyTMVarIO, putTMVar, readTMVar)
import           Effectful.Exception      (SomeException, finally, try)
import           Effectful.FileSystem.IO  (FileSystem, Handle, hClose)
import           Effectful.Process        (CreateProcess (std_err, std_in, std_out),
                                           Process, ProcessHandle,
                                           StdStream (CreatePipe),
                                           createProcess_, waitForProcess)
import           System.Exit              (ExitCode)

class InputSource a where
  isStdStream ::
       (FileSystem :> es) => (Maybe Handle -> Eff es a, Maybe StdStream)

instance InputSource Handle where
  isStdStream = (\(Just h) -> pure h, Just CreatePipe)

class OutputSink a where
  osStdStream :: (FileSystem :> es) => (Maybe Handle -> Eff es a, Maybe StdStream)

instance OutputSink Handle where
  osStdStream = (\(Just h) -> pure h, Just CreatePipe)

data StreamingProcessHandle es =
  StreamingProcessHandle ProcessHandle (TMVar ExitCode) (Eff es ())

streamingProcess ::
     ( InputSource stdin
     , OutputSink stdout
     , OutputSink stderr
     , Process :> es
     , Concurrent :> es
     , FileSystem :> es
     )
  => CreateProcess
  -> Eff es (stdin, stdout, stderr, StreamingProcessHandle es)
streamingProcess cp = do
  let (getStdin, stdinStream) = isStdStream
      (getStdout, stdoutStream) = osStdStream
      (getStderr, stderrStream) = osStdStream
  (stdinH, stdoutH, stderrH, ph) <-
    createProcess_
      "streamingProcess"
      cp
        { std_in = fromMaybe (std_in cp) stdinStream
        , std_out = fromMaybe (std_out cp) stdoutStream
        , std_err = fromMaybe (std_err cp) stderrStream
        }
  ec <- newEmptyTMVarIO
    -- Apparently waitForProcess can throw an exception itself when
    -- delegate_ctlc is True, so to avoid this TMVar from being left empty, we
    -- capture any exceptions and store them as an impure exception in the
    -- TMVar
  _ <-
    forkIOWithUnmask $ \_unmask ->
      try (waitForProcess ph)
        >>= atomically . putTMVar ec . either (throw :: SomeException -> a) id
  let close = mclose stdinH `finally` mclose stdoutH `finally` mclose stderrH
        where
          mclose = maybe (return ()) hClose
  (,,,)
    <$> getStdin stdinH
    <*> getStdout stdoutH
    <*> getStderr stderrH
    <*> return (StreamingProcessHandle ph ec close)

streamingProcessHandleRaw :: StreamingProcessHandle es -> ProcessHandle
streamingProcessHandleRaw (StreamingProcessHandle ph _ _) = ph

-- Since 0.1.4
waitForStreamingProcess ::
     (Concurrent :> es) => StreamingProcessHandle es -> Eff es ExitCode
waitForStreamingProcess = atomically . waitForStreamingProcessSTM

-- | STM version of @waitForStreamingProcess@.
--
-- Since 0.1.4
waitForStreamingProcessSTM :: StreamingProcessHandle es -> STM ExitCode
waitForStreamingProcessSTM = readTMVar . streamingProcessHandleTMVar

streamingProcessHandleTMVar :: StreamingProcessHandle es -> TMVar ExitCode
streamingProcessHandleTMVar (StreamingProcessHandle _ var _) = var

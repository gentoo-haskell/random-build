{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase       #-}

module GHRB.IO.Utils
  ( bStderr
  , stderr
  , stdout
  , bStdout
  , logOutput
  , getArgs
  ) where

import           Control.Applicative           ((<**>))
import           Control.Monad.IO.Class        (MonadIO, liftIO)
import           Control.Monad.Reader          (MonadReader, asks)
import qualified Data.ByteString.Lazy          as BL (appendFile,
                                                      writeFile)
import qualified Data.ByteString.Lazy.Char8    as BL (hPutStrLn, pack)
import           GHRB.Core.Types               (Args, EmergePath,
                                                HaskellUpdaterPath,
                                                Output (DevNull, OutFile, Std),
                                                PqueryPath, args, getEmerge,
                                                getErrMode, getHU,
                                                getOutputMode, getPquery)
import           Options.Applicative           (execParser, fullDesc, helper,
                                                info, progDesc)
import           Prettyprinter                 (Pretty, SimpleDocStream,
                                                defaultLayoutOptions,
                                                layoutPretty, pretty,
                                                unAnnotateS)
import           Prettyprinter.Render.Terminal (AnsiStyle)
import qualified Prettyprinter.Render.Terminal as T (renderLazy)
import qualified Prettyprinter.Render.Text     as TL (renderLazy)
import           System.Directory              (findExecutable)
import           System.Environment            (setEnv)
import           System.Exit                   (die)
import qualified System.IO                     as IO (stderr, stdout)
import qualified Data.Text.Lazy.Encoding as TL (encodeUtf8)

bStdout :: (MonadIO m, MonadReader Args m) => SimpleDocStream AnsiStyle -> m ()
bStdout message = do
  outmode <- asks getOutputMode
  case outmode of
    Std        -> liftIO $ BL.hPutStrLn IO.stdout . TL.encodeUtf8 . T.renderLazy $ message
    OutFile fp -> liftIO $ BL.appendFile fp . TL.encodeUtf8 . TL.renderLazy . unAnnotateS $ message
    DevNull    -> pure ()

stdout :: (MonadIO m, MonadReader Args m, Pretty a) => a -> m ()
stdout = bStdout . layoutPretty defaultLayoutOptions . pretty

logOutput :: MonadIO m => FilePath -> String -> m ()
logOutput filepath message = liftIO $ BL.writeFile filepath . BL.pack $ message

stderr :: (MonadIO m, MonadReader Args m, Pretty a) => a -> m ()
stderr = bStderr . layoutPretty defaultLayoutOptions . pretty

bStderr :: (MonadIO m, MonadReader Args m) => SimpleDocStream AnsiStyle -> m ()
bStderr message = do
  errmode <- asks getErrMode
  case errmode of
    DevNull      -> pure ()
    Std          -> liftIO $ BL.hPutStrLn IO.stderr . TL.encodeUtf8 . T.renderLazy $ message
    (OutFile fp) -> liftIO $ BL.appendFile fp . TL.encodeUtf8 . TL.renderLazy . unAnnotateS $ message

getArgs :: MonadIO m => m Args
getArgs = do
  args' <-
    liftIO
      $ execParser . info (args <**> helper)
      $ (fullDesc
           <> progDesc
                "A utility to repeatedly randomly build haskell packages from ::haskell")
  pquery <-
    if null (getPquery args')
      then pqueryPath
      else pure . getPquery $ args'
  emerge <-
    if null (getEmerge args')
      then emergePath
      else pure . getEmerge $ args'
  hu <-
    if null (getHU args')
      then haskellUpdaterPath
      else pure . getHU $ args'
  pure args' {getPquery = pquery, getEmerge = emerge, getHU = hu}

emergePath :: MonadIO m => m EmergePath
emergePath =
  liftIO (findExecutable "emerge") >>= \case
    Just p -> do
      liftIO $ setEnv "FEATURES" "-getbinpkg"
      pure p
    Nothing ->
      liftIO
        $ die
            "Could not find emerge executable. Install sys-apps/portage first."

-- | Find the path to the @pquery@ executable or throw an error. Caches the
--   result in the case of a success.
pqueryPath :: MonadIO m => m PqueryPath
pqueryPath =
  liftIO (findExecutable "pquery") >>= \case
    Just p -> pure p
    Nothing ->
      liftIO
        $ die
            "Could not find pquery executable. Install sys-apps/pkgcore first."

-- | Find the path to the @haskell-updater@ executable or throw an error.
--   Caches the result in the case of a success. Sets
--   @FEATURES="-getbinpkg"@ to avoid it interfering with this utility.
haskellUpdaterPath :: MonadIO m => m HaskellUpdaterPath
haskellUpdaterPath =
  liftIO (findExecutable "haskell-updater") >>= \case
    Just p -> do
      liftIO $ setEnv "FEATURES" "-getbinpkg"
      pure p
    Nothing ->
      liftIO
        $ die
            "Could not find haskell-updater executable. \
           \Install app-admin/haskell-updater first."

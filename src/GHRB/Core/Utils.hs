module GHRB.Core.Utils
  ( prettySuccess
  , prettyFail
  , prettyPreMerge
  , prettyMessage
  , prettyTry
  ) where

import           GHRB.Core.Types               (failure, message,
                                                preMergeFailure, success, try)
import           Prettyprinter                 (Doc, SimpleDocStream, defaultLayoutOptions,
                                                layoutPretty, pretty, Pretty)
import           Prettyprinter.Render.Terminal (AnsiStyle)

prettify :: (Pretty a) => (Doc AnsiStyle -> Doc AnsiStyle) -> a -> SimpleDocStream AnsiStyle
prettify prettifier =
    layoutPretty defaultLayoutOptions
    . prettifier
    . pretty

prettySuccess :: (Pretty a) => a -> SimpleDocStream AnsiStyle
prettySuccess = prettify success

prettyFail :: (Pretty a) => a -> SimpleDocStream AnsiStyle
prettyFail = prettify failure

prettyPreMerge :: (Pretty a) => a -> SimpleDocStream AnsiStyle
prettyPreMerge = prettify preMergeFailure

prettyMessage :: (Pretty a) => a -> SimpleDocStream AnsiStyle
prettyMessage = prettify message

prettyTry :: (Pretty a) => a -> SimpleDocStream AnsiStyle
prettyTry = prettify try



> module Text.DocTool.DocTool
>     (OutputFile(..)
>     ,Type(..)
>     ,Source(..)
>     ,Title
>     ,docify) where

> import Text.Pandoc
> import Text.XHtml.Transitional hiding (toHtml)
> --import Control.Monad
> --import qualified Language.Haskell.Exts as Exts
> import System.FilePath
> import System.Directory
> import Debug.Trace
> --import Text.Highlighting.Kate
> import Text.Highlighting.Illuminate
> --import Debug.Trace
> import Data.DateTime

> import Data.List


> import Text.DocTool.Parser as Parser

> docify :: FilePath -> [OutputFile] -> IO ()
> docify b ofs = do
>   t <- getCurrentTime
>   let tm = formatDateTime "%D %T" t
>   mapM_ (\f -> putStrLn (showOf f) >> process "0.3.0" tm b f) ofs
>          where
>            showOf (OutputFile _ _ s _) = show s

====================================================================

> data OutputFile = OutputFile Source Type FilePath Title

> data Type = Sql | Lhs | Hs | Txt | Ag | Css
>             deriving Show

> data Source = File FilePath
>             | Text String
>               deriving Show

> type Title = String

> --type ProcessText = String -> String
> --type ProcessPandoc = Pandoc -> Pandoc
> --type ProcessHtml = Html -> Html

=========================================================

> {-ppPandoc :: OutputFile -> IO String
> ppPandoc (OutputFile s t _ _) =
>     asText s >>= return . (toPandoc t |> ppExpr)-}

> asText :: Source -> IO String
> asText (File fp) = readFile fp
> asText (Text a) = return a

> toPandoc :: Type -> String -> Pandoc
> toPandoc t s = {-trace ("toPandoc " ++ show t ++ s) $-}
>                case t of
>                  Lhs -> readLhs s
>                  Sql -> readSource "/*" "*/" "sql" s
>                  Hs -> readSource "{-" "-}" "haskell" s
>                  Ag -> readSource "{-" "-}" "haskell" s
>                  Txt -> readMd s
>                  Css -> readSource "/*" "*/" "css" s

> setTitle :: String -> Pandoc -> Pandoc
> setTitle t (Pandoc m bs) = Pandoc m' bs
>     where
>       m' = m {docTitle = [Str t]}

> toHtml :: Pandoc -> Html
> toHtml pa = writeHtml defaultWriterOptions highlightCode
>     where
>       highlightCode = case pa of
>                           Pandoc m bs -> Pandoc m (map hi bs)
>       hi (CodeBlock a b) =
>          case illuminate (getType a) b of
>            Right result -> RawHtml $ result {-renderHtmlFragment $
>                            formatAsXHtml [] "Haskell" result-}
>            Left  err    -> error $ "Could not parse input: " ++ err
>       hi x = x
>       getType _ = "Haskell"

> wrapHtmlFragment :: String -> Html -> Html
> wrapHtmlFragment ti h =
>   header << [t,c]
>   +++ body << h
>   where
>     t = thetitle << ti
>     c = thelink ! [href "/website/main.css"
>                   ,rel "stylesheet"
>                   ,thetype "text/css"] << ""

bit dodgy

> filterLinks :: String -> String -> String
> filterLinks path = replace
>                           "\"/website/"
>                           ("\"" ++ path)


> toText :: Html -> String
> toText h = renderHtml h

> process :: String -> String -> FilePath -> OutputFile -> IO ()
> process _ _ _ (OutputFile (File f) Css fp _) =
>   copyFile f fp
> process v tm b (OutputFile s t fp ti) = do
>   let hd = wheader v
>       ft = wfooter v tm
>   asText s
>     >>= return . (toPandoc t |> setTitle ti |> toHtml
>                   |> (\h -> hd +++ h +++ ft)
>                   |> wrapHtmlFragment ti |> toText |> filterLinks back)
>     >>= writeFolderFile fp
>   where
>     relpath = makeRelative b fp
>     back = concat $ replicate (length $
>                       splitDirectories $
>                       dropFileName relpath)
>                      "../"

> wheader :: String -> Html
> wheader v =
>   thediv ! [theclass "header"]
>       << a
>   +++ [br,br,br]
>   where
>     a = anchor ! [href "/website/index.txt.html"]
>                    << ("HsSqlPpp-" ++ v)

todo: add the last modified time for each file individually

> wfooter :: String -> String -> Html
> wfooter v d =
>     [br,br,br] +++ di
>   where
>     s = "Copyright 2010 Jake Wheat, generated on "
>          ++ d ++ ", hssqlppp-" ++ v
>     di = thediv ! [theclass "footer"] << s




> writeFolderFile :: FilePath -> String -> IO ()
> writeFolderFile fp t = do
>   createDirectoryIfMissing True $ dropFileName fp
>   writeFile fp t

> infixl 9 |>
> (|>) :: (a -> b) -> (b -> c) -> a -> c
> (|>) = flip (.)



add some sample files: ag lhs hs txt sql
show the pandoc ast
try illuminate, need to write sql highlighter?


> {-ppExpr :: Show s => s -> String
> ppExpr s =
>   case Exts.parseExp (show s) of
>     Exts.ParseOk ast -> Exts.prettyPrint ast
>     x -> error $ show x-}



> -- pure wrappers to do various rendering
> readMd :: String -> Pandoc
> readMd = readMarkdown defaultParserState
>
> readLhs :: String -> Pandoc
> readLhs = readMarkdown ropt
>   where
>     ropt = defaultParserState {
>             stateLiterateHaskell = True
>            }


> readSource :: String -> String -> String -> String -> Pandoc
> readSource sc ec ty txt = either err id $ do
>     ccs <- parseSource sc ec txt
>     return $ convl ccs
>     where
>       err e = trace (show e) $ w $ cb txt
>       convl :: [Cc] -> Pandoc
>       convl cs = w $ concatMap conv cs
>       conv :: Cc -> [Block]
>       conv (Parser.Code c) = cb c
>       conv (Comments m) = case readMarkdown defaultParserState m of
>                            Pandoc _ b -> b
>       cb s = [CodeBlock ("", ["sourceCode", "literate", ty], []) s]
>       w b = Pandoc (Meta{docTitle = [], docAuthors = [], docDate = []}) b

todo:
do hack for =,==,etc. headers
do hack for sql strings in haskell?
add css
add anchors
filter relative links
titles
copyright
header
footer
navigation, sitemap, breadcrumbs

================================================

> illuminate :: String -> String -> Either String String
> illuminate ty txt = do
>     let lexer = lexerByName ty
>     tokens <- tokenize lexer txt
>     let html = toXHtmlCSS defaultOptions tokens
>     return $ showHtmlFragment html


> replace :: (Eq a) => [a] -> [a] -> [a] -> [a]
> replace _ _ [] = []
> replace old new xs@(y:ys) =
>   case stripPrefix old xs of
>     Nothing -> y : replace old new ys
>     Just ys' -> new ++ replace old new ys'
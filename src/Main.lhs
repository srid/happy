-----------------------------------------------------------------------------
$Id: Main.lhs,v 1.17 1998/06/19 13:41:03 simonm Exp $

The main driver.

(c) 1993-1997 Andy Gill, Simon Marlow
-----------------------------------------------------------------------------

> module Main (main) where

> import ParseMonad
> import GenUtils
> import Lexer
> import AbsSyn
> import Grammar
> import Parser
> import First
> import LALR
> import Version
> import ProduceCode (produceParser)
> import Info (genInfoFile)
> import Target (Target(..))
> import GetOpt
> import Set

> import System
> import Char
> import IO
> import Array( Array, assocs, elems, (!) )
> import List( nub )

#ifdef __GLASGOW_HASKELL__
> import PrelGHC (unsafeCoerce#)
#define sCC _scc_
> coerceParser = unsafeCoerce#
#else
> sCC = id
> coerceParser = id
#endif

> main = 

Read and parse the CLI arguments.

>       getArgs				>>= \ args ->
>	main2 args

> main2 :: [String] -> IO ()
> main2 args = 

Read and parse the CLI arguments.

>       case getOpt Permute argInfo (constArgs ++ args) of
>         	(cli,[fl_name],[]) -> runParserGen cli fl_name
>               (cli,[],[]) | DumpVerbose `elem` cli -> copyright
>		(_,_,errors) -> die (concat errors ++ 
>				     usageInfo usageHeader argInfo)

>  where 	
>    runParserGen cli fl_name =

Print out the copyright message if we are in verbose mode.

>       optIO (elem DumpVerbose cli) copyright		>>

Open the file.

>       readFile fl_name		     		>>= \ fl ->
>	possDelit (reverse fl_name) fl			>>= \ (file,name) ->

Parse, using bootstrapping parser.

>	case coerceParser (ourParser file 1) of {
>		FailP err -> die (fl_name ++ ':' : err);
>		OkP abssyn@(AbsSyn hd _ _ tl) -> 

Mangle the syntax into something useful.

>	case sCC "Mangler" (mangler abssyn) of {
>		Failed s -> die (unlines s ++ "\n");
>		Succeeded g -> 

>	let gram@(Grammar gram_info dir term nonterm tys env eof) = g
> 	    term_dir = [ (a,b) | (a,b) <- getTokenSpec dir, a >= first_term]
>	    first_term = getFirstTerm gram_info
>       in


#ifdef DEBUG

>       optPrint cli DumpMangle (putStr (show gram)) >>

#endif


>       let first  	= sCC "First" (mkFirst gram_info)
>	    closures    = sCC "Closures" (precalcClosure0 gram_info)
>           sets  	= sCC "LR0 Sets" (genLR0items gram_info closures)
>	    lainfo@(spont,prop) = sCC "Prop" (propLookaheads gram_info sets first)
>	    la 		= sCC "Calc" (calcLookaheads (length sets)
>					((0,(0,0),[eof]):spont) prop)
>	    items2	= sCC "Merge" (mergeLookaheadInfo la sets)
>           goto   	= sCC "Goto" (genGotoTable gram_info sets)
>           action 	= sCC "Action" (genActionTable gram_info first items2)
>	    (conflictArray,(sr,rr))   = sCC "Conflict" (countConflicts action)
>       in

#ifdef DEBUG

>       optPrint cli DumpLR0 (putStr (show sets))		>>
>       optPrint cli DumpAction (putStr (show action))      	>>
>       optPrint cli DumpGoto (putStr (show goto))          	>>
>       optPrint cli DumpLA (putStr (show lainfo))		>>
>       optPrint cli DumpLA (putStr (show la))			>>

#endif

Report any unused rules and terminals

>	let (unused_rules, unused_terminals) = 
>		find_redundancies gram_info env action
>	in
>	optIO (not (null unused_rules))
>	   (putStr ("unused rules: " ++ show (length unused_rules) ++ "\n")) >>
>	optIO (not (null unused_terminals))
>	   (putStr ("unused terminals: " ++ show (length unused_terminals) ++
>		"\n")) >>

Report any conflicts in the grammar.

>	(if sr /= 0
>		then putStr ("shift/reduce conflicts:  " ++ show sr ++ "\n")
>		else return ())			>>

>	(if rr /= 0
>		then putStr ("reduce/reduce conflicts: " ++ show rr ++ "\n")
>		else return ())			>>

Print out the info file.

>	getInfoFileName name cli		>>= \info_filename ->
>	let info = genInfoFile
>			env
>			(map fst sets)
>			gram_info
>			action
>			goto
>			term_dir
>			conflictArray
>			fl_name
>			unused_rules
>			unused_terminals
>	in

>	(case info_filename of
>		Just s  -> writeFile s info
>		Nothing -> return ())			>>

Now, lets get on with generating the parser.  Firstly, find out what kind
of code we should generate, and where it should go:

>	getTarget cli					>>= \target ->
>	getOutputFileName fl_name cli			>>= \outfilename ->
>	getTemplate template_dir cli			>>= \template' ->
>	getCoerce target cli				>>= \opt_coerce ->
>	let 
>	    template = template_file template' target opt_coerce in

Read in the template file for this target:

>       readFile template				>>= \ templ ->

and generate the code.

>	getMagicName cli				>>= \ magic_name ->
>       let outfile = produceParser 
>                       gram_info
>                       action
>                       goto
>                       (getLexer dir)
>                       term_dir
>                       (getTokenType dir)
>			tys
>			(getParserName dir)
>			(getMonad dir)
>                       hd
>                       tl
>			target
>			opt_coerce
>	    magic_filter = 
>	      case magic_name of
>		Nothing -> id
>		Just name ->
>		  let
>		      small_name = name
>		      big_name = toUpper (head name) : tail name
>		      filter_output ('h':'a':'p':'p':'y':rest) =
>			small_name ++ filter_output rest
>		      filter_output ('H':'a':'p':'p':'y':rest) =
>			big_name ++ filter_output rest
>		      filter_output (c:cs) = c : filter_output cs
>		      filter_output [] = []
>		  in 
>		     filter_output 
>       in

>       writeFile outfilename (magic_filter (outfile ++ templ))

Successfully Finished.

>	}}

-----------------------------------------------------------------------------

> die :: String -> IO a
> die s = hPutStr stderr s >> exitWith (ExitFailure 1)

> dieHappy :: String -> IO a
> dieHappy s = getProgName >>= \prog -> die (prog ++ ": " ++ s)

> optIO :: Bool -> IO a -> IO a
> optIO fg io = if fg then io  else return (error "optIO")

> optPrint cli pass io = 
>       optIO (elem pass cli) (putStr "\n---------------------\n" >> io)

> optDump cli pass io =
> 	optIO (elem pass cli) io

> constArgs = []

-----------------------------------------------------------------------------
Find unused rules and tokens

> find_redundancies 
>	:: GrammarInfo 
>	-> Array Name String
>	-> ActionTable
>	-> ([Int], [String])
>
> find_redundancies g env action_table = 
>	(unused_rules, map (env !) unused_terminals)
>    where
>	actions		 = concat (map assocs (elems action_table))
>	used_rules       = 0 : nub [ r | (_,LR'Reduce{-'-} r) <- actions ]
>	used_tokens      = errorTok : eof : 
>			       nub [ t | (t,LR'Shift{-'-} _ ) <- actions ]
>	terminals        = getTerminals g
>	non_terminals    = getNonTerminals g
>	eof		 = getEOF g
>	n_prods		 = length (getProds g)
>	unused_terminals = filter (`notElem` used_tokens) terminals
>	unused_rules     = filter (`notElem` used_rules ) [0..n_prods-1]

------------------------------------------------------------------------------

> possDelit :: String -> String -> IO (String,String)
> possDelit ('y':'l':'.':nm) fl = return (deLitify fl,reverse nm)
> possDelit ('y':'.':nm) fl     = return (fl,reverse nm)
> possDelit f            fl     = 
>	dieHappy ("`" ++ reverse f ++ "' does not end in `.y' or `.ly'\n")

This was a program hot-spot, but not any more.

> deLitify :: String -> String
> deLitify = deLit 
>  where 
>       deLit ('>':' ':r)  = deLit1 r
>       deLit ('>':'\t':r)  = '\t' : deLit1 r
>       deLit ('>':r)  = error "Error when de-litify-ing"
>       deLit ('\n':r) = '\n' : deLit r
>       deLit r        = deLit2 r
>       deLit1 ('\n':r) = '\n' : deLit r
>       deLit1 (c:r)    = c : deLit1 r
>       deLit1 []       = []
>       deLit2 ('\n':r) = '\n' : deLit r
>       deLit2 (c:r)    = deLit2 r
>       deLit2 []       = []

------------------------------------------------------------------------------
The command line arguments.

> data CLIFlags = DumpMangle
>               | DumpLR0
>               | DumpAction
>               | DumpGoto
>		| DumpLA
>		
>               | DumpVerbose
>		| OptInfoFile (Maybe String)
>		| OptTemplate String
>		| OptMagicName String
>
>		| OptGhcTarget
>		| OptArrayTarget
>		| OptUseCoercions
>		
>		| OptOutputFile String
>  deriving Eq

> argInfo :: [OptDescr CLIFlags]
> argInfo  = [
>    Option ['a'] ["array"] (NoArg OptArrayTarget)
>	"Generate an array-based parser",
>    Option ['i'] ["info"] (OptArg OptInfoFile "FILE")
>	"Output grammar info to FILE",
>    Option ['c'] ["coerce"] (NoArg OptUseCoercions)
>	"Use type coercions (only available with -g)",
>    Option ['g'] ["ghc"]    (NoArg OptGhcTarget)
>	"Use GHC extensions (not available with -a)",
>    Option ['m'] ["magic-name"] (ReqArg OptMagicName "NAME")
>	"Use NAME as the symbol prefix instead of \"happy\"",
>    Option ['o'] ["outfile"] (ReqArg OptOutputFile "FILE")
>	"Write the output to FILE (default: INFILE.hs)",
>    Option ['t'] ["template"] (ReqArg OptTemplate "DIR")
>	"Look in DIR for template files",
>    Option ['v'] ["verbose"] (NoArg DumpVerbose)
>       "Print out version info"

#ifdef DEBUG

Various debugging/dumping options...

>    ,
>    Option [] ['mangle'] (NoArg DumpMangle)
>	"Dump mangled input",
>    Option [] ['lr0'] (NoArg DumpLR0)
>	"Dump LR0 item sets",
>    Option [] ['action'] (NoArg DumpAction)
>	"Dump action table",
>    Option [] ['goto'] (NoArg DumpGoto)
>	"Dump goto table",
>    Option [] ['lookaheads'] (NoArg DumpLA)
>	"Dump lookahead info",

#endif

>    ]

-----------------------------------------------------------------------------
How would we like our code to be generated?

> optToTarget OptGhcTarget 	= Just TargetGhc
> optToTarget OptArrayTarget 	= Just TargetArrayBased
> optToTarget _			= Nothing

> template_file temp_dir target coerce
>   = temp_dir ++ base
>  where  
>	base = case target of
>		 TargetHaskell 	  -> "/HappyTemplate"
>		 TargetGhc | coerce -> "/HappyTemplate-coerce"
>			   | otherwise -> "/HappyTemplate-ghc"
>		 TargetArrayBased -> "/HappyTemplate-arrays"

------------------------------------------------------------------------------
Extract various command-line options.

> getTarget cli = case [ t | (Just t) <- map optToTarget cli ] of
> 			(t:ts) | all (==t) ts -> return t
>			[]  -> return TargetHaskell
>			_   -> dieHappy "multiple target options\n"

> getOutputFileName ip_file cli
> 	= case [ s | (OptOutputFile s) <- cli ] of
>		[]  -> return (base ++ ".hs")
>			where (base,ext) = break (== '.') ip_file
>		[f] -> return f
>		_   -> dieHappy "multiple -o options\n"

> getInfoFileName base cli
> 	= case [ s | (OptInfoFile s) <- cli ] of
>		[]	   -> return Nothing
>		[Nothing]  -> return (Just (base ++ ".info"))
>		[Just f]   -> return (Just f)
>		_   -> dieHappy "multiple -i options\n"

> getTemplate def cli
> 	= case [ s | (OptTemplate s) <- cli ] of
>		[]	   -> return def
>		[f]        -> return f
>		_          -> dieHappy "multiple templates specified\n"

> getMagicName cli
> 	= case [ s | (OptMagicName s) <- cli ] of
>		[]	   -> return Nothing
>		[f]        -> return (Just (map toLower f))
>		_          -> dieHappy "multiple --magic-name options\n"

> getCoerce target cli
>	= if OptUseCoercions `elem` cli 
>	     then case target of
>			TargetGhc -> return True
>			otherwise -> dieHappy "-c/--coerce may only be used \ 
>					      \in conjunction with -g/--ghc\n"
>	     else return False

------------------------------------------------------------------------------

> copyright :: IO ()
> copyright = putStr (unlines  [
>  "Happy Version " ++ version ++ " Copyright (c) 1993-1996 Andy Gill, Simon Marlow (c) Simon Marlow 1997-1998","",
>  "Happy is a Yacc for Haskell, and comes with ABSOLUTELY NO WARRANTY.",
>  "This program is free software; you can redistribute it and/or modify",
>  "it under the terms given in the file 'LICENSE' distributed with",
>  "the Happy sources.\n"])

> usageHeader = "happy [OPTION...] file"

> syntax = unlines [
>   "syntax: happy [-v] [-o | --outfile <file>] [--info [<file>]]",
>   "		   [-1.2] [--template <dir>]",
>   "              [-g | --ghc] [-a | --array] <file>\n" ]


> template_dir = "/usr/local/lib/happy"

-----------------------------------------------------------------------------

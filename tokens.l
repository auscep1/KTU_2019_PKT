%{
#include <string>
#include <stack>
#include "AstNode.h"
#include "parser.hpp"
#define SAVE_TOKEN yylval.string = new std::string(yytext, yyleng)
#define TOKEN(t) (yylval.token = t)

extern "C" int yywrap() { return 1; }

int yycolumn = 1;

#define YYERROR_VERBOSE 1
int yyerror(char const * s )
{
	printf("ERROR %s in '%s' at line %d col %d\n", s, yytext, yylineno, yycolumn);
	printf("	parsed loc %d.%d-%d.%d\n", yylloc.first_line, yylloc.first_column, yylloc.last_line, yylloc.last_column);
	return 1;
}

std::string g_str;

/* globals to track current indentation */
int current_line_indent = 0;	/* indentation of the current line */
int indent_level = 0;		/* indentation level passed to the parser */
std::stack<int> curr_indents;
int first_time = 1 ;

int parsing_error = 0;

std::stack<std::string> fileNames;
std::stack<int> lineNo;
std::vector<std::string> libPaths;

#define YY_USER_ACTION do { \
			if( yylloc.last_line < yylineno ) yycolumn = 1 ; \
			yylloc.first_line = yylloc.last_line = yylineno; \
			yylloc.first_column = yycolumn; yylloc.last_column = yycolumn + (int)yyleng - 1; \
			yycolumn += (int)yyleng; \
			yylloc.file_name = fileNames.top(); \
		} while(0) ;

%}

%option yylineno

%x indent 
%s normal 
%x str qstr
%x comment
%x incl

dig		 	[0-9]
num1			[-+]?{dig}+\.([eE][-+]?{dig}+)?
num2			[-+]?{dig}*\.{dig}+([eE][-+]?{dig}+)?
number			{num1}|{num2}

%%
			if( first_time ) {
				first_time = 0;
				curr_indents.push(0);
				lineNo.push(yylineno);
				BEGIN indent;
			}

						
import			BEGIN(incl);
<incl>[ \t]*		/* eat the whitespace */
<incl>[^ \t\n\r]+	/* got the include file name */{
				std::string fileName = yytext;
				std::size_t pos = fileName.find(".pkt2");
				if( pos == std::string::npos ) {
					fileName += ".pkt2";
				}
				for( auto libpath : libPaths ) {
					yyin = fopen( (libpath + fileName).c_str() , "r" );
					if( yyin )
						break;
				}
				if ( ! yyin ) {
					printf( "%s in %s line %d\n", (std::string("Failed to load import file ") + fileName).c_str(), fileNames.top().c_str(), yylineno );
					parsing_error = 1;
					yyterminate();
				} 
				else {
					fileNames.push(yytext);
					lineNo.push(yylineno);
					yylineno = yycolumn = 1;
					yylloc.first_line = yylloc.first_column =				yylloc.last_line = yylloc.last_column = 1;
					yypush_buffer_state(yy_create_buffer( yyin, YY_BUF_SIZE ));
				}
				BEGIN(normal);
			}
		 

\/\.\.*			BEGIN(comment);
<comment>\.\.\/.*	BEGIN(normal); /*long comment end, but should be \n also*/
<comment>.*		;/* eat everything */
<comment>\n		;/* eat everything until \n*/

\"			g_str = "";	BEGIN(str);
'			g_str = "";	BEGIN(qstr);

<str>\" 		{	 	
				BEGIN(normal);
				yylval.string = new std::string(g_str);
				return TSTR;
			}
<qstr>' 		{	 
				BEGIN(normal);
				yylval.string = new std::string(g_str);
				return TSTR;
			}

<str,qstr>\\n	 	g_str += "\n";
<str,qstr>\\t	 	g_str += "\t";
<str,qstr>\\r	 	g_str += "\r";
<str>\\\"		g_str += "\"";
<qstr>\\\'		g_str += "'";

<str,qstr>\\(.|\n)	g_str += yytext[1];

<str>[^\\\"]+		g_str += std::string(yytext);
<qstr>[^\\']+		g_str += std::string(yytext);

<indent>" "		{ current_line_indent++; }
<indent>"\t"		{ current_line_indent = (current_line_indent + 8) & ~7; }
<indent>"\n"		{ current_line_indent = 0; yycolumn = 1;/*ignoring blank line */ }
<indent>"\r"		{ current_line_indent = 0; yycolumn = 1;/*ignoring blank line */ }


<indent>.		{
				unput(*yytext);
				yycolumn--;
				/*if (current_line_indent > curr_indents.top()) {
					curr_indents.push(current_line_indent);
					return TOKEN(TBLOCKSTART);
				} 
				else if (current_line_indent < curr_indents.top()) {
					curr_indents.pop();
					return TOKEN(TBLOCKEND);
				} 
				else {*/
					BEGIN(normal);
				/*}*/
			}

<normal>"\n"			{ current_line_indent = 0; BEGIN( indent); yycolumn = 1; }
<<EOF>>			{ 
				yypop_buffer_state();
				fileNames.pop();
				yylineno = lineNo.top();
				lineNo.pop();
				if( !YY_CURRENT_BUFFER ) {
					yyterminate();
				}
				if( curr_indents.size() > 1 ) {
					curr_indents.pop();
					return TOKEN(TBLOCKEND);
				}
			}
									

\r			/* cr are ignored */
"if"			return TOKEN(TIF);
"else"			return TOKEN(TELSE);
"#debugstart"		return TOKEN(DEBUGSTART);
"#debugend"		return TOKEN(DEBUGEND);
"</"			return TOKEN(TBLOCKSTART);
"/>"			return TOKEN(TBLOCKEND);
">>"[ \t]*[\n]		return TOKEN(TRETURN_SIMPLE); 	/*return*/
">>"			return TOKEN(TRETURN);		/*return*/
"!!"			return TOKEN(TNOT); 		/*not*/
"&&"			return TOKEN(TAND); 		/*and*/
"||"			return TOKEN(TOR); 		/*or*/
"@"			return TOKEN(TDEF); 		/*@ - to call a function*/
"var"			return TOKEN(TVAR);
"while"			return TOKEN(TWHILE);
	/* "createfile"		return TOKEN(TCREATEFILE); */	/*create file*/
	/*"appendfile"		return TOKEN(TAPPENDFILE); */
"is"			return TOKEN(IS);
"true"			SAVE_TOKEN; return TBOOL;
"false"			SAVE_TOKEN; return TBOOL;
"to"			return TOKEN(TTO);
~.*	 		/* comments one line til nl */
[ \t\n]			/* ignore */;
[a-zA-Z_][a-zA-Z0-9_&%\$\?\-]*	SAVE_TOKEN; return TIDENTIFIER;
-?[0-9]+		SAVE_TOKEN; return TINTEGER;
{number}		SAVE_TOKEN; return TDOUBLE;
"->"			return TOKEN(TRANGE);
"::"			return TOKEN(TRANGE);
"="	 		return TOKEN(TEQUAL);
"=="			return TOKEN(TCEQ);
"<>"			return TOKEN(TCNE);
"=<"			return TOKEN(TLTLT); 	/*array_add_element*/
"<"	 		return TOKEN(TCLO); 	/*comparison lower*/
"<="			return TOKEN(TCLE);	/*comparison lower equal*/
">"	 		return TOKEN(TCGR); 	/*comparison greater*/
">="			return TOKEN(TCGE);	/*comparison greater equal*/
"("	 		return TOKEN(TLPAREN);
")"	 		return TOKEN(TRPAREN);
"."	 		return TOKEN(TDOT);
","	 		return TOKEN(TCOMMA);
"+"	 		return TOKEN(TPLUS);
"-"	 		return TOKEN(TMINUS);
"*"	 		return TOKEN(TMUL);
"/"	 		return TOKEN(TDIV);
":"	 		return TOKEN(TCOLON);
"["	 		return TOKEN(TLBRACKET);
"]"	 		return TOKEN(TRBRACKET);
.		 	printf("line %d, len %d Unknown token %s !\n", yylineno, yyleng, yytext); yyterminate();

%%

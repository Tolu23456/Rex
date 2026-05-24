; tokens.inc - Rex Token Definitions

%ifndef TOKENS_INC
%define TOKENS_INC

%assign TOK_EOF      0
%assign TOK_INDENT   1
%assign TOK_DEDENT   2
%assign TOK_NEWLINE  3

; Keywords
%assign TOK_PROT     10
%assign TOK_RETURN   11
%assign TOK_IF       12
%assign TOK_ELSE     13
%assign TOK_FOR      14
%assign TOK_IN       15
%assign TOK_USE      16
%assign TOK_MM       17
%assign TOK_GC       18
%assign TOK_OUTPUT   19
%assign TOK_INT      20
%assign TOK_FLOAT    21
%assign TOK_STR      22
%assign TOK_DICT     23
%assign TOK_TUP      24
%assign TOK_SET      25
%assign TOK_COMPLEX  26
%assign TOK_NONE     27
%assign TOK_TRUE     28
%assign TOK_FALSE    29
%assign TOK_UNKNOWN  30

; Identifiers and Literals
%assign TOK_IDENT    40
%assign TOK_LIT_INT  41
%assign TOK_LIT_FLT  42
%assign TOK_LIT_STR  43
%assign TOK_LIT_CPX  44

; Operators and Punctuation
%assign TOK_ASSIGN   50 ; =
%assign TOK_COLON    51 ; :
%assign TOK_COMMA    52 ; ,
%assign TOK_ARROW    53 ; ->
%assign TOK_LPAREN   54 ; (
%assign TOK_RPAREN   55 ; )
%assign TOK_LBRACK   56 ; [
%assign TOK_RBRACK   57 ; ]
%assign TOK_LBRACE   58 ; {
%assign TOK_RBRACE   59 ; {
%assign TOK_DOT      60 ; .
%assign TOK_DOTDOT   61 ; ..
%assign TOK_AT       62 ; @
%assign TOK_LTGT     63 ; <{ or }> (sets)

; Comparisons and Arithmetic
%assign TOK_EQ       70 ; ==
%assign TOK_NE       71 ; !=
%assign TOK_GE       72 ; >=
%assign TOK_LE       73 ; <=
%assign TOK_GT       74 ; >
%assign TOK_LT       75 ; <
%assign TOK_PLUS     76 ; +
%assign TOK_MINUS    77 ; -
%assign TOK_MUL      78 ; *
%assign TOK_DIV      79 ; /

%endif

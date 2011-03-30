/***************************************************************************
 * This file is part of the Lemberg assembler.
 * Copyright (C) 2011 Wolfgang Puffitsch
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 ***************************************************************************/

%{
	#include <stdlib.h>
	#include <stdio.h>
	#include <stdarg.h>
	#include <string.h>

	#include "code.h"
	#include "exprs.h"
	#include "symtab.h"
	#include "optab.h"

	int yylex(void);
	void yyerror(const char *);	

	int line_number = 1;
	long pos = 0;
	long code_size = 0;
	struct bundle *code;

	static void emit_bundle(struct bundle);
	static void emit_string(const char *);
	static void fix_offset(struct asmop*);

/* 	yydebug = 1; */
%}

%union {
	int           opcode;
	long long     intval;
	char *        strval;
	struct expr   exprval;
	struct cond   cond;
	struct asmop  asmop;
	struct op     op;
	struct bundle bundle;
}

%token IF DEST BSEP ALIGN QUAD LONG SHORT BYTE ASCII COMM

%token <intval>  CLUST FLAG REG EXT FREG DREG
%token <strval>  STR
%token <exprval> NUM EXPR SYM
%token <opcode>  NOP THREEOP ONEOP NULLOP LDIOP WBOP CMPOP BRANCHOP GLOBOP
                 LDGAOP STOREOP LOADOP LDXOP STXOP MULOP CCOP
                 FOP FTHREEOP FCMPOP FTWOOP FONEOP F2DOP
                 DTHREEOP DCMPOP DTWOOP DONEOP D2FOP

%type <intval>   NotOptFlag
%type <exprval>  Constant
%type <cond>     Condition
%type <asmop>    AsmOp
%type <op>       Operation
%type <bundle>   Bundle Directive

%start Input

%%

Input : Input Bundle
	  {
		  emit_bundle($2);
	  }
      | Input Label
	  | Input Directive
	  {
		  emit_bundle($2);
	  }
      | /* empty */
;

LFOpt : NewLine | /* empty */
;

Label: SYM ':' LFOpt
      {
		  push_sym($1.strval, pos);
      }
;

Directive : ALIGN NUM NewLine
          {
			  int align = $2.intval;
			  $$.type = -2;
			  $$.size = pos % align == 0 ? 0 : align - pos % align;
			  $$.raw = NULL_EXPR;
			  pos = ((pos+align-1) / align) * align;
		  }
          | QUAD Constant NewLine
		  {
			  $$.type = -1;
			  $$.size = 8;
			  $$.raw = $2;
			  pos += 8;
		  }
          | LONG Constant NewLine
		  {
			  $$.type = -1;
			  $$.size = 4;
			  $$.raw = $2;
			  pos += 4;
		  }
          | SHORT Constant NewLine
		  {
			  $$.type = -1;
			  $$.size = 2;
			  $$.raw = $2;
			  pos += 2;
		  }
          | BYTE Constant NewLine
		  {
			  $$.type = -1;
			  $$.size = 1;
			  $$.raw = $2;
			  pos += 1;
		  }
          | ASCII STR NewLine
		  {
			  emit_string($2);
			  $$.type = -1;
			  $$.size = 0;
			  $$.raw = NULL_EXPR;
		  }
          | COMM SYM ',' NUM ',' NUM NewLine
          {
			  int align = $6.intval;
			  $$.type = -1;
			  $$.size = pos % align == 0 ? 0 : align - pos % align;
			  $$.raw = NULL_EXPR;
			  pos = ((pos+align-1) / align) * align;			  

			  push_sym($2.strval, pos);
			  $$.size += $4.intval;
			  pos += $4.intval;
		  }
;

Bundle : NOP Constant NewLine BSEP NewLine
       {
		   pos += 1;

		   $$.type = 0;
		   $$.size = 1;
		   $$.raw = $2;
       }
       | Operation BSEP NewLine
       {
		   pos += 4;
		   fix_offset(&($1.op));

		   $$.type = (1 << $1.clust);
		   $$.size = 4;
		   $$.op[$1.clust] = $1;
       }
       | Operation Operation BSEP NewLine
       {
		   pos += 7;
		   fix_offset(&($1.op));
		   fix_offset(&($2.op));

		   $$.type = (1 << $1.clust) | (1 << $2.clust);
		   $$.size = 7;
		   $$.op[$1.clust] = $1;
		   $$.op[$2.clust] = $2;
       }
       | Operation Operation Operation BSEP NewLine
       {
		   pos += 10;
		   fix_offset(&($1.op));
		   fix_offset(&($2.op));
		   fix_offset(&($3.op));

		   $$.type = (1 << $1.clust) | (1 << $2.clust) | (1 << $3.clust);
		   $$.size = 10;
		   $$.op[$1.clust] = $1;
		   $$.op[$2.clust] = $2;
		   $$.op[$3.clust] = $3;
       }
       | Operation Operation Operation Operation BSEP NewLine
       {
		   pos += 13;
		   fix_offset(&($1.op));
		   fix_offset(&($2.op));
		   fix_offset(&($3.op));
		   fix_offset(&($4.op));

		   $$.type = (1 << $1.clust) | (1 << $2.clust) | (1 << $3.clust) | (1 << $4.clust);
		   $$.size = 13;
		   $$.op[$1.clust] = $1;
		   $$.op[$2.clust] = $2;
		   $$.op[$3.clust] = $3;
		   $$.op[$4.clust] = $4;
       }
;

Operation : CLUST AsmOp NewLine
		  {
			  $$.clust = $1;
			  $$.op = $2;
		  }
;

Condition : IF FLAG
		  {
			  $$.cond = COND_TRUE;
			  $$.flag = $2;
		  }
          | IF '!' FLAG
		  {
			  $$.cond = COND_FALSE;
			  $$.flag = $3;
		  }
		  | /* empty */
		  {
			  $$.cond = COND_TRUE; /* "if c0" is implicit */
			  $$.flag = 0;
		  }
;

AsmOp : Condition THREEOP REG ',' Constant DEST REG
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = $3;
		  $$.fmt.B.src2.imm = $5;
		  $$.fmt.B.dest = $7;
		  $$.fmt.B.imm = 1;
		  $$.fmt.B.cond = $1;
      }
      | Condition THREEOP REG ',' REG DEST REG
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = $3;
		  $$.fmt.B.src2.reg = $5;
		  $$.fmt.B.dest = $7;
		  $$.fmt.B.imm = 0;
		  $$.fmt.B.cond = $1;
      }
      | Condition ONEOP Constant
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = 0;
		  $$.fmt.B.src2.imm = $3;
		  $$.fmt.B.dest = 0;
		  $$.fmt.B.imm = 1;
		  $$.fmt.B.cond = $1;
      }
      | Condition ONEOP REG
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = $3;
		  $$.fmt.B.src2.reg = $3;
		  $$.fmt.B.dest = 0;
		  $$.fmt.B.imm = 0;
		  $$.fmt.B.cond = $1;
      }
      | Condition NULLOP
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = 0;
		  $$.fmt.B.src2.reg = 0;
		  $$.fmt.B.dest = 0;
		  $$.fmt.B.imm = 0;
		  $$.fmt.B.cond = $1;
      }
      | Condition CMPOP REG ',' Constant DEST FLAG
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = $3;
		  $$.fmt.B.src2.imm = $5;
		  $$.fmt.B.dest = $7;
		  $$.fmt.B.imm = 1;
		  $$.fmt.B.cond = $1;
      }
      | Condition CMPOP REG ',' REG DEST FLAG
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = $3;
		  $$.fmt.B.src2.reg = $5;
		  $$.fmt.B.dest = $7;
		  $$.fmt.B.imm = 0;
		  $$.fmt.B.cond = $1;
      }
      | Condition LDIOP Constant DEST REG
      {
		  $$.op = $2;
		  $$.fmt.I.dest = $5;
		  $$.fmt.I.val = $3;
		  $$.fmt.I.cond = $1;
      }
      | Condition WBOP REG ',' Constant
      {
		  $$.op = $2;
		  $$.fmt.I.dest = $3;
		  $$.fmt.I.val = $5;
		  $$.fmt.I.cond = $1;
      }
      | Condition LOADOP REG ',' Constant
      {
		  $$.op = $2;
		  $$.fmt.L.addr = $3;
		  $$.fmt.L.offset = $5;
		  $$.fmt.L.cond = $1;
      }
      | Condition STOREOP Constant ',' REG ',' Constant
      {
		  $$.op = $2;
		  $$.fmt.S.val.imm = $3;
		  $$.fmt.S.addr = $5;
		  $$.fmt.S.offset = $7.intval;
		  $$.fmt.S.imm = 1;
		  $$.fmt.S.cond = $1;
      }
      | Condition STOREOP REG ',' REG ',' Constant
      {
		  $$.op = $2;
		  $$.fmt.S.val.reg = $3;
		  $$.fmt.S.addr = $5;
		  $$.fmt.S.offset = $7.intval;
		  $$.fmt.S.imm = 0;
		  $$.fmt.S.cond = $1;
      }
      | Condition BRANCHOP Constant
      {		  
		  $$.op = $2;
		  $$.fmt.J.target.offset = $3;
		  $$.fmt.J.imm = 1;
		  $$.fmt.J.cond = $1;
      }
      | Condition BRANCHOP REG
      {
		  $$.op = $2;
		  $$.fmt.J.target.reg = $3;
		  $$.fmt.J.imm = 0;
		  $$.fmt.J.cond = $1;
      }
      | Condition LDXOP EXT DEST REG
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = $3;
		  $$.fmt.B.src2.imm = NULL_EXPR;
		  $$.fmt.B.dest = $5;
		  $$.fmt.B.imm = 1;
		  $$.fmt.B.cond = $1;
	  }
      | Condition LDXOP EXT ',' Constant  DEST REG
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = $3;
		  $$.fmt.B.src2.imm = $5;
		  $$.fmt.B.dest = $7;
		  $$.fmt.B.imm = 1;
		  $$.fmt.B.cond = $1;
	  }
      | Condition LDXOP EXT ',' REG DEST REG
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = $3;
		  $$.fmt.B.src2.reg = $5;
		  $$.fmt.B.dest = $7;
		  $$.fmt.B.imm = 0;
		  $$.fmt.B.cond = $1;
	  }
      | Condition STXOP REG DEST EXT
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = $3;
		  $$.fmt.B.src2.reg = 0;
		  $$.fmt.B.dest = $5;
		  $$.fmt.B.imm = 0;
		  $$.fmt.B.cond = $1;
	  }
      | Condition MULOP REG ',' Constant DEST EXT
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = $3;
		  $$.fmt.B.src2.imm = $5;
		  $$.fmt.B.dest = 0; /* destinition is implicit */
		  $$.fmt.B.imm = 1;
		  $$.fmt.B.cond = $1;
      }
      | Condition MULOP REG ',' REG DEST EXT
      {
		  $$.op = $2;
		  $$.fmt.B.src1 = $3;
		  $$.fmt.B.src2.reg = $5;
		  $$.fmt.B.dest = 0; /* destinition is implicit */
		  $$.fmt.B.imm = 0;
		  $$.fmt.B.cond = $1;
      }
      | GLOBOP Constant
      {
		  $$.op = $1;
		  $$.fmt.G.address = $2;
      }
      | LDGAOP Constant DEST REG
      {
		  $$.op = $1;
		  $$.fmt.H.dest = $4;
		  $$.fmt.H.address = $2;
      }
      | Condition CCOP THREEOP NotOptFlag ',' NotOptFlag DEST FLAG
	  {
		  int pattern = 0;
		  int notA = 0;
		  int notB = 0;
		  switch ($3) {
		  case OP_AND: pattern = 0; break;
		  case OP_OR:  pattern = 1; break;
		  case OP_XOR: pattern = 2; break;
		  default: fprintf(stderr, "error: Invalid combination operation.");
		  }
		  if ($4 < 0) {
			  notA = 1;
			  $4 = ~$4;
		  }
		  if ($6 < 0) {
			  notB = 1;
			  $6 = ~$6;
		  }
		  pattern = (pattern << 6) | (notA << 5) | (($4 & 0x03) << 3) | (notB << 2) | ($6 & 0x03);
		  $$.op = $2;
		  $$.fmt.I.dest = $8;
		  $$.fmt.I.val.strval = NULL;
		  $$.fmt.I.val.intval = pattern;
		  $$.fmt.I.cond = $1;
	  }
      | Condition FOP FTHREEOP FREG ',' FREG DEST FREG
	  {
		  $$.op = $2;
		  $$.fmt.F.dest = $8;
		  $$.fmt.F.src1 = $6;
		  $$.fmt.F.src2 = $4;
		  $$.fmt.F.op   = $3;
		  $$.fmt.F.cond = $1;
	  }
      | Condition FOP FCMPOP FREG ',' FREG DEST FREG
	  {
		  $$.op = $2;
		  $$.fmt.F.dest = $8;
		  $$.fmt.F.src1 = $6;
		  $$.fmt.F.src2 = $4;
		  $$.fmt.F.op   = $3;
		  $$.fmt.F.cond = $1;
	  }
      | Condition FOP FTWOOP FREG DEST FREG
	  {
		  $$.op = $2;
		  $$.fmt.F.dest = $6;
		  $$.fmt.F.src1 = $4;
		  $$.fmt.F.src2 = $3;
		  $$.fmt.F.op   = OP_FSUBOP;
		  $$.fmt.F.cond = $1;
	  }
      | Condition FOP FONEOP DEST FREG
	  {
		  $$.op = $2;
		  $$.fmt.F.dest = $5;
		  $$.fmt.F.src1 = 0;
		  $$.fmt.F.src2 = $3;
		  $$.fmt.F.op   = OP_FSUBOP;
		  $$.fmt.F.cond = $1;
	  }
      | Condition FOP F2DOP FREG DEST DREG
	  {
		  $$.op = $2;
		  $$.fmt.F.dest = $6;
		  $$.fmt.F.src1 = $4;
		  $$.fmt.F.src2 = $3;
		  $$.fmt.F.op   = OP_FSUBOP;
		  $$.fmt.F.cond = $1;
	  }
      | Condition FOP DTHREEOP DREG ',' DREG DEST DREG
	  {
		  $$.op = $2;
		  $$.fmt.F.dest = $8;
		  $$.fmt.F.src1 = $6;
		  $$.fmt.F.src2 = $4;
		  $$.fmt.F.op   = $3;
		  $$.fmt.F.cond = $1;
	  }
      | Condition FOP DCMPOP DREG ',' DREG DEST FREG
	  {
		  $$.op = $2;
		  $$.fmt.F.dest = $8;
		  $$.fmt.F.src1 = $6;
		  $$.fmt.F.src2 = $4;
		  $$.fmt.F.op   = $3;
		  $$.fmt.F.cond = $1;
	  }
      | Condition FOP DTWOOP DREG DEST DREG
	  {
		  $$.op = $2;
		  $$.fmt.F.dest = $6;
		  $$.fmt.F.src1 = $4;
		  $$.fmt.F.src2 = $3;
		  $$.fmt.F.op   = OP_FSUBOP;
		  $$.fmt.F.cond = $1;
	  }
      | Condition FOP DONEOP DEST DREG
	  {
		  $$.op = $2;
		  $$.fmt.F.dest = $5;
		  $$.fmt.F.src1 = 0;
		  $$.fmt.F.src2 = $3;
		  $$.fmt.F.op   = OP_FSUBOP;
		  $$.fmt.F.cond = $1;
	  }
      | Condition FOP D2FOP DREG DEST FREG
	  {
		  $$.op = $2;
		  $$.fmt.F.dest = $6;
		  $$.fmt.F.src1 = $4;
		  $$.fmt.F.src2 = $3;
		  $$.fmt.F.op   = OP_FSUBOP;
		  $$.fmt.F.cond = $1;
	  }
;

NotOptFlag: '!' FLAG
          {
			  $$ = ~$2;
		  }
          | FLAG
          {
			  $$ = $1;
		  }

Constant: NUM
        | SYM
        | EXPR
;

NewLine: NewLine '\n'
       | '\n'
;

%%

void yyerror(const char *msg)
{
	fprintf(stderr, "%d: %s\n", line_number, msg);
	exit(EXIT_FAILURE);
}

static void emit_bundle(struct bundle bundle)
{
	code_size++;
	code = realloc(code, sizeof(struct bundle)*code_size);
	code[code_size-1] = bundle;
}

static void emit_string(const char *str)
{
	const char *p;
	char c;
	struct bundle bundle;
	for (p = str; *p != '\0'; ++p)
		{
			if (*p == '\\')
				{
					p++;
					switch (p[0])
						{
						case 'b': c = '\b'; break;
						case 'f': c = '\f'; break;
						case 'n': c = '\n'; break;
						case 'r': c = '\r'; break;
						case 't': c = '\t'; break;
						case '\\': c = '\\'; break;
						case '"': c = '"';  break;
						case '0': case '1': case '2': case '3':
						case '4': case '5': case '6': case '7':
							if (p[1] >= '0' && p[1] <= '7' &&
								p[2] >= '0' && p[2] <= '7')
								{
									c = ((p[0]-'0') << 6) | ((p[1]-'0') << 3) | (p[2]-'0');
									p += 2;
									break;
								}
						default:
							fprintf(stderr, "error: Invalid escaped character: `%c'", *p);
						}
				} 
			else
				{
					c = *p;
				}

			bundle.type = -1;
			bundle.size = 1;
			bundle.raw = NULL_EXPR;
			bundle.raw.intval = c;

			pos += 1;

			emit_bundle(bundle);
		}
}

static void fix_offset(struct asmop *op)
{
	if (op->op == OP_BR && op->fmt.J.imm)
		{
			if (op->fmt.J.target.offset.strval == NULL)
				{
					op->fmt.J.target.offset.intval -= pos;
				}
			else
				{
					char *strval = op->fmt.J.target.offset.strval;
					char *relexpr = malloc(strlen(strval)+16);
					sprintf(relexpr, "%s-0x%lx", strval, pos);
					op->fmt.J.target.offset.strval = relexpr;
				}
			/* fprintf(stderr, "BR: %lld/%s\n", */
			/* 		op->fmt.J.target.offset.intval, */
			/* 		op->fmt.J.target.offset.strval); */
		}
}

static int buf_pos = 0;
static char buffer [4];

/* big-endian variant for emitting code */
static void dump_words(unsigned long long val, int bytes)
{
	int i;
	for (i = 0; i < bytes; i++)
		{
			buffer[buf_pos++] = (val >> 8*(bytes-i-1)) & 0xFF;
			if (buf_pos == 4)
				{
					printf("%d, // %08x\n",
						   ((buffer[0] << 24) & 0xff000000)
						   | ((buffer[1] << 16) & 0x00ff0000)
						   | ((buffer[2] << 8) & 0x0000ff00)
						   | ((buffer[3] << 0) & 0x000000ff),
						   ((buffer[0] << 24) & 0xff000000)
						   | ((buffer[1] << 16) & 0x00ff0000)
						   | ((buffer[2] << 8) & 0x0000ff00)
						   | ((buffer[3] << 0) & 0x000000ff));
					buf_pos = 0;
				}
		}
}

/* little-endian variant for emitting data */
static void dump_dwords(unsigned long long val, int bytes)
{
	int i;
	for (i = 0; i < bytes; i++)
		{
			buffer[buf_pos++] = (val >> 8*i) & 0xFF;
			if (buf_pos == 4)
				{
					printf("%d,\n",
						   ((buffer[3] << 24) & 0xff000000)
						   | ((buffer[2] << 16) & 0x00ff0000)
						   | ((buffer[1] << 8) & 0x0000ff00)
						   | ((buffer[0] << 0) & 0x000000ff));
					buf_pos = 0;
				}
		}
}

static void dump_padding(int type)
{
	while(buf_pos != 0)
		{
			if (type == -1)
				dump_dwords(0, 1);
			else
				dump_words(0, 1);
		}
}

static void dump()
{
	int i;
	int type = 0;

	for (i = 0; i < code_size; i++)
		{
			switch (code[i].type)
				{
				case -2:
					if (type == -1)
						dump_dwords(expr_evaluate(code[i].raw), code[i].size);
					else
						dump_words(expr_evaluate(code[i].raw), code[i].size);
					break;
				case -1:
					dump_dwords(expr_evaluate(code[i].raw), code[i].size);
					break;
				case 0x0:
					dump_words(code[i].type | (expr_evaluate(code[i].raw) & 0x0f), 1);
					break;
				case 0x1:
					dump_words(((code[i].type & 0x0F) << 28) 
							   | (conv_asmop(code[i].op[0].op) << 3), 4);
					break;
				case 0x2:
					dump_words(((code[i].type & 0x0F) << 28)
							   | (conv_asmop(code[i].op[1].op) << 3), 4);
					break;
				case 0x4:
					dump_words(((code[i].type & 0x0F) << 28)
							   | (conv_asmop(code[i].op[2].op) << 3), 4);
					break;
				case 0x8:
					dump_words(((code[i].type & 0x0F) << 28)
							   | (conv_asmop(code[i].op[3].op) << 3), 4);
					break;
				case 0x3:
					dump_words(((code[i].type & 0x0F) << 28)
							   | (conv_asmop(code[i].op[0].op) << 3)
							   | (conv_asmop(code[i].op[1].op) >> 22), 4);
					dump_words(((conv_asmop(code[i].op[1].op) & 0x3FFFFF) << 2), 3);
					break;
				case 0x5:
					dump_words(((code[i].type & 0x0F) << 28)
							   | (conv_asmop(code[i].op[0].op) << 3)
							   | (conv_asmop(code[i].op[2].op) >> 22), 4);
					dump_words(((conv_asmop(code[i].op[2].op) & 0x3FFFFF) << 2), 3);
					break;
				case 0x9:
					dump_words(((code[i].type & 0x0F) << 28) 
							   | (conv_asmop(code[i].op[0].op) << 3)
							   | (conv_asmop(code[i].op[3].op) >> 22), 4);
					dump_words(((conv_asmop(code[i].op[3].op) & 0x3FFFFF) << 2), 3);
					break;
				case 0x6:
					dump_words(((code[i].type & 0x0F) << 28)
							   | (conv_asmop(code[i].op[1].op) << 3)
							   | (conv_asmop(code[i].op[2].op) >> 22), 4);
					dump_words(((conv_asmop(code[i].op[2].op) & 0x3FFFFF) << 2), 3);
					break;
				case 0xA:
					dump_words(((code[i].type & 0x0F) << 28)
							   | (conv_asmop(code[i].op[1].op) << 3)
							   | (conv_asmop(code[i].op[3].op) >> 22), 4);
					dump_words(((conv_asmop(code[i].op[3].op) & 0x3FFFFF) << 2), 3);
					break;
				case 0xC:
					dump_words(((code[i].type & 0x0F) << 28)
							   | (conv_asmop(code[i].op[2].op) << 3)
							   | (conv_asmop(code[i].op[3].op) >> 22), 4);
					dump_words(((conv_asmop(code[i].op[3].op) & 0x3FFFFF) << 2), 3);
					break;
				case 0x7:
					dump_words(((code[i].type & 0x0F) << 28) 
							   | (conv_asmop(code[i].op[0].op) << 3)
							   | (conv_asmop(code[i].op[1].op) >> 22), 4);
					dump_words(((conv_asmop(code[i].op[1].op) & 0x3FFFFF) << 10)
							   | (conv_asmop(code[i].op[2].op) >> 15), 4);
					dump_words(((conv_asmop(code[i].op[2].op) & 0x7FFF) << 1), 2);
					break;
				case 0xB:
					dump_words(((code[i].type & 0x0F) << 28) 
							   | (conv_asmop(code[i].op[0].op) << 3) 
							   | (conv_asmop(code[i].op[1].op) >> 22), 4);
					dump_words(((conv_asmop(code[i].op[1].op) & 0x3FFFFF) << 10)
							   | (conv_asmop(code[i].op[3].op) >> 15), 4);
					dump_words(((conv_asmop(code[i].op[3].op) & 0x7FFF) << 1), 2);
					break;
				case 0xD:
					dump_words(((code[i].type & 0x0F) << 28)
							   | (conv_asmop(code[i].op[0].op) << 3)
							   | (conv_asmop(code[i].op[2].op) >> 22), 4);
					dump_words(((conv_asmop(code[i].op[2].op) & 0x3FFFFF) << 10) 
							   | (conv_asmop(code[i].op[3].op) >> 15), 4);
					dump_words(((conv_asmop(code[i].op[3].op) & 0x7FFF) << 1), 2);
					break;
				case 0xE:
					dump_words(((code[i].type & 0x0F) << 28)
							   | (conv_asmop(code[i].op[1].op) << 3)
							   | (conv_asmop(code[i].op[2].op) >> 22), 4);
					dump_words(((conv_asmop(code[i].op[2].op) & 0x3FFFFF) << 10)
							   | (conv_asmop(code[i].op[3].op) >> 15), 4);
					dump_words(((conv_asmop(code[i].op[3].op) & 0x7FFF) << 1), 2);
					break;
				case 0xF:
					dump_words(((code[i].type & 0x0F) << 28) 
							   | (conv_asmop(code[i].op[0].op) << 3)
							   | (conv_asmop(code[i].op[1].op) >> 22), 4);
					dump_words(((conv_asmop(code[i].op[1].op) & 0x3FFFFF) << 10)
							   | (conv_asmop(code[i].op[2].op) >> 15), 4);
					dump_words(((conv_asmop(code[i].op[2].op) & 0x7FFF) << 17)
							   | (conv_asmop(code[i].op[3].op) >> 8), 4);
					dump_words((conv_asmop(code[i].op[3].op) & 0xFF), 1);
					break;
				default:
					fprintf(stderr, "error: unknown bundle type\n");
				}
			if (code[i].type != -2)
				type = code[i].type;
		}
	dump_padding(type);
}

int main(int argc, char **argv)
{
	code = malloc(sizeof(struct bundle));

	init_symtab();

	yyparse();

	dump();

	print_symtab(stderr, 1);

	return 0;
}
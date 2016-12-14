%{
#include <iostream>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <list>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/Function.h>
#include "SymbolTable.h"
#include "Type.h"
    extern "C" int yylex();
    extern "C" int yyparse();
    extern "C" FILE *yyin;
    void yyerror(const char *s);

    // Module, function, basic block, and builder
    llvm::Module *module;
    llvm::Function *function;
    llvm::BasicBlock *basic_block;
    llvm::IRBuilder<> *builder;

    // Variables introduced to track nested function scopes
    // implementing these as a list allows us to treat them as a stack to push and pop the current function we're generating llvm code for
    std::list<llvm::Function *> outerFunctions;           // keep track of the outer functions when inner functions are declared
    std::list<llvm::BasicBlock *> outerFunctionBasicBlocks;       // keep track of what basic block the outer function was in the middle of

    // Environment: stack of symbol tables. It is actually implemented as a list
    // to facilitate the traversal of symbol tables.
    std::list<SymbolTable *> environment;
    SymbolTable * currentScope;
    %}

    %token TokenInt
    %token TokenFloat
    %token TokenVoid
    %token TokenStruct
    %token<name> TokenId
    %token<value> TokenNumber
    %token TokenOpenCurly
    %token TokenCloseCurly
    %token TokenOpenSquare
    %token TokenCloseSquare
    %token TokenOpenPar
    %token TokenClosePar
    %token TokenSemicolon
    %token TokenComma
    %token TokenPoint
    %token TokenEqual
    %left TokenLogicalOr
    %left TokenLogicalAnd
    %token TokenLogicalNot
    %nonassoc TokenGreaterThan
    %nonassoc TokenLessThan
    %nonassoc TokenGreaterEqual
    %nonassoc TokenLessEqual
    %nonassoc TokenNotEqual
    %nonassoc TokenDoubleEqual
    %left TokenPlus TokenMinus
    %left TokenMult TokenDiv
    %token TokenIf
    %nonassoc TokenThen
    %nonassoc TokenElse
    %token TokenWhile
    %token TokenReturn
    %type<type> Type
    %type<type> Pointer
    %type<indices> Indices
    %type<llvalue> Expression
    %type<lvalue> LValue
    %type<if_statement> IfStatement
    %type<formal_arguments> FormalArguments
    %type<formal_arguments> FormalArgumentsComma
    %type<symbol> FunctionDeclaration
    %type<actual_arguments> ActualArguments
    %type<actual_arguments> ActualArgumentsComma
    %union {
        char *name;
        llvm::Value *llvalue;
        int value;
        Type *type;
        std::list<int> *indices;

        // For LValue
        struct {
            Type *type;
            llvm::Value *lladdress;
            std::vector<llvm::Value *> *llindices;
        } lvalue;

        // For mid-rule actions in logical expressions
        struct {
            llvm::BasicBlock *lhs_basic_block;
            llvm::BasicBlock *rhs_basic_block;
            llvm::BasicBlock *end_basic_block;
        } logical;

        // For mid-rule actions in "if" statement
        struct {
            llvm::BasicBlock *then_basic_block;
            llvm::BasicBlock *else_basic_block;
            llvm::BasicBlock *end_basic_block;
        } if_statement;

        // For mid-rule actions in "while" statement
        struct {
            llvm::BasicBlock *cond_basic_block;
            llvm::BasicBlock *body_basic_block;
            llvm::BasicBlock *end_basic_block;
        } while_statement;

        // For 'FormalArguments' and 'FormalArgumentsComma'
        std::vector<Symbol *> *formal_arguments;

        // For 'FunctionDeclaration'
        Symbol *symbol;

        // For 'ActualArguments' and 'ActualArgummentsComma'
        std::vector<llvm::Value *> *actual_arguments;
    }

%%
Start:
    Declarations Statements

Declarations:
    | Declarations Declaration

Declaration:
    Pointer TokenId Indices TokenSemicolon
{

    // Get top symbol table
    SymbolTable *symbol_table = currentScope;

    // Create new symbol
    Symbol *symbol = new Symbol($2);
    symbol->type = $1;
    symbol->index = symbol_table->size();

    // Process indices
    for (int index : *$3)
    {
        Type *type = new Type(Type::KindArray);
        type->num_elem = index;
        type->subtype = symbol->type;
        type->lltype = llvm::ArrayType::get(symbol->type->lltype, index);
        symbol->type = type;
    }

    // Symbol in global scope
    if (symbol_table->getScope() == SymbolTable::ScopeGlobal)
        symbol->lladdress = new llvm::GlobalVariable(
                *module,
                symbol->type->lltype,
                false,
                llvm::GlobalValue::ExternalLinkage,
                nullptr,
                symbol->getName());

    // Symbol in local scope
    else if (symbol_table->getScope() == SymbolTable::ScopeLocal)
        symbol->lladdress = builder->CreateAlloca(symbol->type->lltype,
                nullptr, Symbol::getTemp());

    // Insert in symbol table
    std::cerr << "ADDING SYMBOL:\t";
    symbol->dump();
    symbol_table->addSymbol(symbol);
    symbol_table->dump();
}

| FunctionDeclaration TokenOpenCurly
{
    // Push new local symbol table
    SymbolTable *symbol_table = new SymbolTable(SymbolTable::ScopeLocal, currentScope);
    environment.push_back(symbol_table);
    currentScope = symbol_table;

    // Keep track of the outer function and current basic block if there is one
    llvm::Function* outerFunction = function;
    outerFunctions.push_back(outerFunction);
    llvm::BasicBlock* outerFunctionBasicBlock = basic_block;
    outerFunctionBasicBlocks.push_back(outerFunctionBasicBlock);

    // Current LLVM function
    function = llvm::cast<llvm::Function>($1->lladdress);
    function->dump();

    // Create entry basic block
    basic_block = llvm::BasicBlock::Create(
            llvm::getGlobalContext(),
            "entry",
            function);
    builder->SetInsertPoint(basic_block);

    // Add arguments to the stack
    int index = 0;
    for (llvm::Function::arg_iterator it = function->arg_begin(),
            end = function->arg_end();
            it != end;
            ++it)
    {
        // Name argument
        Symbol *argument = (*$1->type->arguments)[index++];
        it->setName(argument->getName());

        // Check to see if this arg is inherited or not
        auto parent_symbol_it = symbol_table->getParentSymbols().find(argument->getName());

        // Create symbol
        Symbol *symbol = new Symbol(argument->getName());
        symbol->type = argument->type;

        // If it wasn't inherited
        if (parent_symbol_it == symbol_table->getParentSymbols().end()) 
        {
            // Save as a local symbol
            symbol_table->addSymbol(symbol);

            // Emit 'alloca' instruction
            symbol->lladdress = builder->CreateAlloca(symbol->type->lltype,
                nullptr, Symbol::getTemp());

            // Emit 'store' instruction
            builder->CreateStore(it, symbol->lladdress);

        }
    }

}

Declarations Statements TokenCloseCurly
{

    // Return statement, if not present
    if (!basic_block->getTerminator()) {
        std::cerr << "Creating return void for function:\t" << function->getName().str() << "\n";
        builder->CreateRetVoid();
    }

    // Restore the outer function and basic block
    basic_block = outerFunctionBasicBlocks.back();
    outerFunctionBasicBlocks.pop_back();
    function = outerFunctions.back();
    outerFunctions.pop_back();
    if (basic_block)
        builder->SetInsertPoint(basic_block);

    // Pop local symbol table
    currentScope = currentScope->getParentTable();
}

| FunctionDeclaration TokenSemicolon
FunctionDeclaration:
Pointer TokenId TokenOpenPar FormalArguments TokenClosePar
{

    std::cerr << "\nGenerating llvm for function declaration: " << $2 << "\n";

    // Create type
    Type *type = new Type(Type::KindFunction);
    type->rettype = $1;
    type->arguments = $4;

    // add arguments for all inherited values
    // These arguments will be pointers to the values that should be modified
    std::unordered_map<std::string, Symbol *> inheritedSymbols = currentScope->getAllSymbols();
    for (auto it = inheritedSymbols.begin(); it != inheritedSymbols.end(); it++) {
        // create a symbol pointing to the inherited symbol
        Symbol *symbol = new Symbol(it->first);
        symbol->type = new Type(Type::KindPointer);
        symbol->type->subtype = it->second->type;
        symbol->type->lltype = llvm::PointerType::get(it->second->type->lltype, 0);
        symbol->index = type->arguments->size();
        type->arguments->push_back(symbol);
    }

    // Create symbol
    Symbol *symbol = new Symbol($2);
    symbol->type = type;
    $$ = symbol;

    // Add to current symbol table
    currentScope->addSymbol(symbol);

    // Create function type
    std::vector<llvm::Type *> types;
    for (Symbol *symbol : *$4)
        types.push_back(symbol->type->lltype);
    llvm::FunctionType *function_type = llvm::FunctionType::get(
            $1->lltype,
            types,
            false);

    // Insert function
    symbol->lladdress = module->getOrInsertFunction($2,
            function_type);
}

FormalArguments:
{
    $$ = new std::vector<Symbol *>();
}

| FormalArgumentsComma Pointer TokenId
{
    Symbol *symbol = new Symbol($3);
    symbol->type = $2;
    symbol->index = $1->size();
    $$->push_back(symbol);
}

FormalArgumentsComma:
{
    $$ = new std::vector<Symbol *>();
}

| FormalArgumentsComma Pointer TokenId TokenComma
{
    Symbol *symbol = new Symbol($3);
    symbol->type = $2;
    symbol->index = $1->size();
    $$->push_back(symbol);
}

Indices:
{
    $$ = new std::list<int>();
}

| TokenOpenSquare TokenNumber TokenCloseSquare Indices
{
    $$ = $4;
    $$->push_back($2);
}

Pointer:
Type
{
    $$ = $1;
}

| Pointer TokenMult
{
    $$ = new Type(Type::KindPointer);
    $$->subtype = $1;
    $$->lltype = llvm::PointerType::get($1->lltype, 0);
}

Type:
TokenInt
{
    $$ = new Type(Type::KindInt);
    $$->lltype = llvm::Type::getInt32Ty(llvm::getGlobalContext());
}

| TokenFloat
{
    $$ = new Type(Type::KindFloat);
    $$->lltype = llvm::Type::getFloatTy(llvm::getGlobalContext());
}

| TokenVoid
{
    $$ = new Type(Type::KindVoid);
    $$->lltype = llvm::Type::getVoidTy(llvm::getGlobalContext());
}

| TokenStruct TokenOpenCurly
{

    // Push new symbol table to environment
    SymbolTable *symbol_table = new SymbolTable(SymbolTable::ScopeStruct, currentScope);
    environment.push_back(symbol_table);
    currentScope = symbol_table;

    // Create type
    $<type>$ = new Type(Type::KindStruct);
    $<type>$->symbol_table = symbol_table;
}

Declarations TokenCloseCurly
{

    // Forward type
    $$ = $<type>3;

    // LLVM structure
    std::vector<llvm::Type *> lltypes;
    currentScope->getLLVMTypes(lltypes);
    $$->lltype = llvm::StructType::create(llvm::getGlobalContext(), lltypes);

    // Pop symbol table from environment
    currentScope = currentScope->getParentTable();
}

Statements:
| Statements Statement
Statement:
Declaration { }
| Expression TokenSemicolon
| LValue TokenEqual Expression TokenSemicolon
{
    llvm::Value *lladdress = $1.llindices->size() > 1 ?
        builder->CreateGEP($1.lladdress, *$1.llindices,
                Symbol::getTemp()) :
        $1.lladdress;
    builder->CreateStore($3, lladdress);
}

| TokenReturn Expression TokenSemicolon
{
    std::cerr << "Creating return expression\n";
    builder->CreateRet($2);
}

| TokenOpenCurly
{
    // Push new local symbol table
    SymbolTable *symbol_table = new SymbolTable(SymbolTable::ScopeLocal, currentScope);
    environment.push_back(symbol_table);
    currentScope = symbol_table;
}

Statements TokenCloseCurly
{

    // Pop symbol table
    currentScope = currentScope->getParentTable();
}

| IfStatement %prec TokenThen
{

    // Emit unconditional to 'end' basic block
    builder->CreateBr($1.end_basic_block);

    // Move to 'end' basic block
    basic_block = $1.end_basic_block;
    builder->SetInsertPoint(basic_block);
}

| IfStatement TokenElse
{

    // Create separate 'else' and 'end' basic blocks
    $<if_statement>$.then_basic_block = $1.then_basic_block;
    $<if_statement>$.else_basic_block = $1.else_basic_block;
    $<if_statement>$.end_basic_block = llvm::BasicBlock::Create(
            llvm::getGlobalContext(),
            Symbol::getBasicBlock(),
            function);

    // Emit unconditional branch to 'end' basic block
    builder->CreateBr($<if_statement>$.end_basic_block);

    // Move to 'else' basic block
    basic_block = $<if_statement>$.else_basic_block;
    builder->SetInsertPoint(basic_block);
}

Statement
{

    // Emit unconditional branch to 'end' basic block
    builder->CreateBr($<if_statement>3.end_basic_block);

    // Move to 'end' basic block
    basic_block = $<if_statement>3.end_basic_block;
    builder->SetInsertPoint(basic_block);
}

| TokenWhile
{

    // Create 'cond', 'body', and 'end' basic blocks
    $<while_statement>$.cond_basic_block = llvm::BasicBlock::Create(
            llvm::getGlobalContext(),
            Symbol::getBasicBlock(),
            function);
    $<while_statement>$.body_basic_block = llvm::BasicBlock::Create(
            llvm::getGlobalContext(),
            Symbol::getBasicBlock(),
            function);
    $<while_statement>$.end_basic_block = llvm::BasicBlock::Create(
            llvm::getGlobalContext(),
            Symbol::getBasicBlock(),
            function);

    // Emit unconditional branch
    builder->CreateBr($<while_statement>$.cond_basic_block);

    // Continue in 'cond' basic block
    basic_block = $<while_statement>$.cond_basic_block;
    builder->SetInsertPoint(basic_block);
}

TokenOpenPar Expression TokenClosePar
{

    // Emit conditional branch
    builder->CreateCondBr($4,
            $<while_statement>2.body_basic_block,
            $<while_statement>2.end_basic_block);

    // Continue in 'body' basic block
    basic_block = $<while_statement>2.body_basic_block;
    builder->SetInsertPoint(basic_block);
}

Statement
{

    // Emit unconditional branch
    builder->CreateBr($<while_statement>2.cond_basic_block);

    // Continue in 'end' basic block
    basic_block = $<while_statement>2.end_basic_block;
    builder->SetInsertPoint(basic_block);
}

IfStatement:
TokenIf TokenOpenPar Expression TokenClosePar
{

    // Create 'if' and 'else' basic blocks, assume 'end' is same as 'else'.
    $<if_statement>$.then_basic_block = llvm::BasicBlock::Create(
            llvm::getGlobalContext(),
            Symbol::getBasicBlock(),
            function);
    $<if_statement>$.else_basic_block = llvm::BasicBlock::Create(
            llvm::getGlobalContext(),
            Symbol::getBasicBlock(),
            function);
    $<if_statement>$.end_basic_block = $<if_statement>$.else_basic_block;

    // Emit conditional branch
    builder->CreateCondBr($3,
            $<if_statement>$.then_basic_block,
            $<if_statement>$.else_basic_block);

    // Continue in 'then' basic block
    basic_block = $<if_statement>$.then_basic_block;
    builder->SetInsertPoint(basic_block);
}

Statement
{
    $$.then_basic_block = $<if_statement>5.then_basic_block;
    $$.else_basic_block = $<if_statement>5.else_basic_block;
    $$.end_basic_block = $<if_statement>5.end_basic_block;
}

Expression:
LValue
{
    llvm::Value *lladdress = $1.llindices->size() > 1 ?
        builder->CreateGEP($1.lladdress, *$1.llindices,
                Symbol::getTemp()) :
        $1.lladdress;
    $$ = builder->CreateLoad(lladdress, Symbol::getTemp());
}

| TokenNumber
{
    llvm::Type *lltype = llvm::Type::getInt32Ty(llvm::getGlobalContext());
    $$ = llvm::ConstantInt::get(lltype, $1);
}

| Expression TokenPlus Expression
{
    $$ = builder->CreateBinOp(llvm::Instruction::Add, $1, $3,
            Symbol::getTemp());
}

| Expression TokenMinus Expression
{
    $$ = builder->CreateBinOp(llvm::Instruction::Sub, $1, $3,
            Symbol::getTemp());
}

| Expression TokenMult Expression
{
    $$ = builder->CreateBinOp(llvm::Instruction::Mul, $1, $3,
            Symbol::getTemp());
}

| Expression TokenDiv Expression
{
    $$ = builder->CreateBinOp(llvm::Instruction::SDiv, $1, $3,
            Symbol::getTemp());
}

| TokenOpenPar Expression TokenClosePar
{
    $$ = $2;
}

| Expression TokenGreaterThan Expression
{
    $$ = builder->CreateICmpSGT($1, $3, Symbol::getTemp());
}

| Expression TokenLessThan Expression
{
    $$ = builder->CreateICmpSLT($1, $3, Symbol::getTemp());
}

| Expression TokenGreaterEqual Expression
{
    $$ = builder->CreateICmpSGE($1, $3, Symbol::getTemp());
}

| Expression TokenLessEqual Expression
{
    $$ = builder->CreateICmpSLE($1, $3, Symbol::getTemp());
}

| Expression TokenDoubleEqual Expression
{
    $$ = builder->CreateICmpEQ($1, $3, Symbol::getTemp());
}

| Expression TokenNotEqual Expression
{
    $$ = builder->CreateICmpNE($1, $3, Symbol::getTemp());
}

| Expression TokenLogicalOr
{

    // Save current basic block
    $<logical>$.lhs_basic_block = basic_block;

    // Create RHS and end basic blocks
    $<logical>$.rhs_basic_block = llvm::BasicBlock::Create(
            llvm::getGlobalContext(),
            Symbol::getBasicBlock(),
            function);
    $<logical>$.end_basic_block = llvm::BasicBlock::Create(
            llvm::getGlobalContext(),
            Symbol::getBasicBlock(),
            function);

    // Emit conditional branch
    builder->CreateCondBr($1,
            $<logical>$.end_basic_block,
            $<logical>$.rhs_basic_block);

    // Set current basic block to RHS
    basic_block = $<logical>$.rhs_basic_block;
    builder->SetInsertPoint(basic_block);
}

Expression
{

    // Emit unconditional branch
    builder->CreateBr($<logical>3.end_basic_block);

    // Move to end basic block
    basic_block = $<logical>3.end_basic_block;
    builder->SetInsertPoint(basic_block);

    // Emit phi instruction
    llvm::PHINode *phi = builder->CreatePHI(
            llvm::IntegerType::getInt1Ty(llvm::getGlobalContext()),
            2, Symbol::getTemp());
    phi->addIncoming($1, $<logical>3.lhs_basic_block);
    phi->addIncoming($4, $<logical>3.rhs_basic_block);
    $$ = phi;
}

| Expression TokenLogicalAnd
{

    // Save current basic block
    $<logical>$.lhs_basic_block = basic_block;

    // Create RHS and end basic blocks
    $<logical>$.rhs_basic_block = llvm::BasicBlock::Create(
            llvm::getGlobalContext(),
            Symbol::getBasicBlock(),
            function);
    $<logical>$.end_basic_block = llvm::BasicBlock::Create(
            llvm::getGlobalContext(),
            Symbol::getBasicBlock(),
            function);

    // Emit conditional branch
    builder->CreateCondBr($1,
            $<logical>$.rhs_basic_block,
            $<logical>$.end_basic_block);

    // Set current basic block to RHS
    basic_block = $<logical>$.rhs_basic_block;
    builder->SetInsertPoint(basic_block);
}

Expression
{

    // Emit unconditional branch
    builder->CreateBr($<logical>3.end_basic_block);

    // Move to end basic block
    basic_block = $<logical>3.end_basic_block;
    builder->SetInsertPoint(basic_block);

    // Emit phi instruction
    llvm::PHINode *phi = builder->CreatePHI(
            llvm::IntegerType::getInt1Ty(llvm::getGlobalContext()),
            2, Symbol::getTemp());
    phi->addIncoming($1, $<logical>3.lhs_basic_block);
    phi->addIncoming($4, $<logical>3.rhs_basic_block);
    $$ = phi;
}

| TokenId TokenOpenPar ActualArguments TokenClosePar
{

    // Search function in local scope
    SymbolTable *symbol_table = currentScope;
    Symbol *symbol = symbol_table->getSymbol($1);

    // Look up the scope tree until we find something or hit global scope
    while (!symbol && symbol_table->getParentTable()) {
        std::cerr << "LOOKIN SOME MORE\n";
        symbol_table = symbol_table->getParentTable();
        symbol = symbol_table->getSymbol($1);
    }

    // Undeclared, or not a function
    if (!symbol || symbol->type->getKind() != Type::KindFunction)
    {
        std::cerr << "Identifier is not a function: " << $1 << '\n';
        exit(1);
    }

    // let's cast the symbol to a function so we can get a list of arguments
    llvm::Function * callee = llvm::cast<llvm::Function>(symbol->lladdress);

    // Find and add all values that will be inherited by the function 
    // to the list of actual arguments
    int index = 0;
    for (llvm::Function::arg_iterator it = callee->arg_begin(),
            end = callee->arg_end();
            it != end;
            ++it)
    {
        // get argument
        Symbol *argument = (*symbol->type->arguments)[index++];

        // ignore the explicitly declared arguments, they should already be there
        if (index < $3->size()) continue;

        // check locally for the variable to pass down
        std::cerr << "DOIN IT\n";
        Symbol * stackFrameArg = currentScope->getSymbol(argument->getName());
        if (stackFrameArg) {
            $3->push_back(builder->CreateGEP(stackFrameArg->lladdress, *(new std::vector<llvm::Value *>()), Symbol::getTemp()));
        }
    }

    // Invoke
    $$ = builder->CreateCall(symbol->lladdress,
            *$3,
            symbol->type->rettype->getKind() == Type::KindVoid ?
            "" : Symbol::getTemp());
}

ActualArguments:
{
    $$ = new std::vector<llvm::Value *>();
}

| ActualArgumentsComma Expression
{
    $$ = $1;
    $$->push_back($2);
}

ActualArgumentsComma:
{
    $$ = new std::vector<llvm::Value *>();
}

| ActualArgumentsComma Expression TokenComma
{
    $$ = $1;
    $$->push_back($2);
}

LValue:
TokenId
{
    // Search symbol in local scope
    SymbolTable *symbol_table = currentScope;
    Symbol *symbol = symbol_table->getSymbol($1);

    // Check if this symbol was inherited
    if (!symbol) {
        auto it = symbol_table->getParentSymbols().find($1);
        if (it != symbol_table->getParentSymbols().end()) {
            symbol = it->second;
        }
    }

    // If we still don't have it, See if it's in the global scope
    if (!symbol)
        symbol = environment.front()->getSymbol($1);


    // Undeclared in this scope and parent scopes
    if (!symbol)
    {
        currentScope->dump();
        std::cerr << "Undeclared identifier: " << $1 << '\n';
        exit(1);
    }

    //std::cerr << "found symbol:\t";
    //symbol->dump();

    // Save info
    $$.type = symbol->type;
    $$.lladdress = symbol->lladdress;
    $$.llindices = new std::vector<llvm::Value *>();

    // Add initial index set to 0
    llvm::Type *lltype = llvm::Type::getInt32Ty(llvm::getGlobalContext());
    llvm::Value *llindex = llvm::ConstantInt::get(lltype, 0);
    $$.llindices->push_back(llindex);
}

| LValue TokenOpenSquare Expression TokenCloseSquare
{

    // Check that L-value is array
    if ($1.type->getKind() != Type::KindArray)
    {
        std::cerr << "L-value is not an array\n";
        exit(1);
    }

    // Add index
    $$.llindices = $1.llindices;
    $$.llindices->push_back($3);

    // Type and address
    $$.type = $1.type->subtype;
    $$.lladdress = $1.lladdress;
}

| LValue TokenPoint TokenId
{

    // Check that L-value is a structure
    if ($1.type->getKind() != Type::KindStruct)
    {
        std::cerr << "L-value is not a struct\n";
        exit(1);
    }

    // Find symbol in structure
    Symbol *symbol = $1.type->symbol_table->getSymbol($3);
    if (!symbol)
    {
        std::cerr << "Invalid field: " << $3 << '\n';
        exit(1);
    }

    // Add index
    llvm::Type *lltype = llvm::Type::getInt32Ty(llvm::getGlobalContext());
    llvm::Value *llindex = llvm::ConstantInt::get(lltype, symbol->index);
    $$.llindices = $1.llindices;
    $$.llindices->push_back(llindex);

    // Type and address
    $$.type = symbol->type;
    $$.lladdress = $1.lladdress;
}

    %%
int main(int argc, char **argv)
{

    // Syntax
    if (argc != 2)
    {
        std::cerr << "Syntax: ./main <file>\n";
        exit(1);
    }

    // Open file in 'yyin'
    yyin = fopen(argv[1], "r");
    if (!yyin)
    {
        std::cerr << "Cannot open file\n";
        exit(1);
    }

    // LLVM context, builder, and module
    llvm::LLVMContext &context = llvm::getGlobalContext();
    builder = new llvm::IRBuilder<>(context);
    module = new llvm::Module("TestModule", context);

    // Push global symbol table to environment
    // Parent symbol table for global is null
    SymbolTable *global_symbol_table = new SymbolTable(SymbolTable::ScopeGlobal, nullptr);
    environment.push_back(global_symbol_table);
    currentScope = global_symbol_table;

    // Parse input until there is no more
    do
    {
        yyparse();
    } while (!feof(yyin));

    environment.back()->dump();

    // Dump module
    std::cerr << "\n\n\n\n\n================================ LLVM CODE ================================\n\n\n";
    module->dump();
    std::cerr << "\n\n\n============================== END LLVM CODE ==============================\n\n\n\n\n";
    return 0;
}

void yyerror(const char *s)
{
    currentScope->dump();
    std::cerr << s << std::endl;
    exit(1);
}


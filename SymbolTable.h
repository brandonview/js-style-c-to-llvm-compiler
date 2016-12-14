#ifndef SYMBOL_TABLE_H
#define SYMBOL_TABLE_H
#include <unordered_map>
#include <string>
#include <llvm/IR/Module.h>
#include "Type.h"
// Forward declaration
class Type;
class Symbol
{
    // Symbol name
    std::string name;
    // Index of next temporary variable
    static int temp_index;

    // Index of next basic block
    static int basic_block_index;
    public:
    /// Constructor
    Symbol(const std::string &name) : name(name) { }
    /// Return the symbol name
    const std::string &getName() { return name; }
    /// Symbol type
    Type *type = nullptr;
    /// Index for a symbol in a symbol table with scope set to
    /// 'ScopeStruct'.
    int index = 0;
    /// LLVM address of the variable for symbols in a symbol table with
    /// its scope set to 'ScopeGlobal' or 'ScopeLocal'.
    llvm::Value *lladdress = nullptr;
    /// Dump information about the symbol
    void dump(int indent = 0);
    /// Return the name of a new temporary variable
    static std::string getTemp();

    /// Return the name of a new basic block 
    static std::string getBasicBlock();
};

class SymbolTable
{
    public:
        /// Possible scopes for the symbol table.
        enum Scope
        {
            ScopeInvalid,
            ScopeGlobal,
            ScopeLocal,
            ScopeStruct
        };
    private:
        // Parent scope
        SymbolTable* parentTable;
        // Symbol table scope
        Scope scope;
        // Symbols
        std::unordered_map<std::string, Symbol *> symbols;

        // The stack frame containing symbols inherited from the parent
        // If not overridden locally, these values should be restored when exiting the scope of a SymbolTable
        std::unordered_map<std::string, Symbol *> parentSymbols;
    public:
        /// Constructor
        SymbolTable(Scope scope, SymbolTable* parentTable) : 
                scope(scope), 
                parentTable(parentTable)
        { 
            // note - parentSymbols is intentionally passed by value since values overridden locally
            // by reinitializing them should be removed and tracked as local but should be left in the parent scope
            if (parentTable)
            {
                parentSymbols = parentTable->getAllSymbols(); 
                // Debug hack to see if functions are actually receiving parent symbols before creation, delete before turning in
                std::cerr << "Values inherited by new scope:\n";
                for (auto it = parentSymbols.begin(); it != parentSymbols.end(); it++) {
                    std::cerr << "Symbol Table Key : " << it->first << "\n";
                    it->second->dump(1);
                }
            }
        }
        /// Return the symbol table scope
        Scope getScope() { return scope; }
        /// Return a symbol given its name, or nullptr if not found.
        Symbol *getSymbol(const std::string &name);
        /// Add symbol to table - should only be called if the symbol is initialized in this scope
        /// i.e. don't add a symbol for a variable inherited from an outer scope
        void addSymbol(Symbol *symbol)
        {
            // add to list of local symbols
            symbols[symbol->getName()] = symbol;

            // remove from the list of parent symbols since it's reinitialized in a local scope
           auto matchingParentSymbol = parentSymbols.find(symbol->getName());
           if (matchingParentSymbol != parentSymbols.end()) {
               parentSymbols.erase(matchingParentSymbol);
           }
        }
        /// Get the map of all symbols available to this scope by value. This is 
        /// useful when creating a child scope that needs to inherit all symbols
        std::unordered_map<std::string, Symbol *> getAllSymbols() 
        {
            std::unordered_map<std::string, Symbol *> allSymbols;
            if (scope != ScopeGlobal) {
                // if we're not in a global scope, add all of our symbols that aren't functions
                for (auto it = symbols.begin(); it != symbols.end(); it++) {
                    if (it->second->type->getKind() != Type::KindFunction) {
                        allSymbols[it->first] = it->second;
                    }
                }
            }
            allSymbols.insert(parentSymbols.begin(), parentSymbols.end());

            return allSymbols;
        }
        /// Dump symbol table to standard output
        void dump(int indent = 0);
        /// Return number of symbols in the symbol table. This is useful to
        /// calculate the index of the next symbol in a data structure.
        int size() { return symbols.size(); }
        /// Return the LLVM types of all symbols in the symbol table, sorted
        /// by their index. This is useful for constructing LLVM struct types.
        void getLLVMTypes(std::vector<llvm::Type *> &types);
        /// Return the parent table that this table was created as a child of
        SymbolTable* getParentTable() { return parentTable; }
        /// get the parent symbols that may have been modified by this scope
        std::unordered_map<std::string, Symbol *> getParentSymbols() { return parentSymbols; }
};
#endif

// A global variable is modified globally when modified in a local scope

int a;
a = 0;

void foo() {
    a = a + 1;
}

// Although it won't be explicitly clear in the llvm generated,
// calling foo() three times should cause the value of a to be 3
// Each call should reference the same llvm variable for var a
foo();
foo();
foo();

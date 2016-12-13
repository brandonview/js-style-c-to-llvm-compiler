// A global variable is modified globally when modified in a local scope

int a;

void foo() {
    a = a + 1;
}

// Although it won't be explicitly clear in the llvm generated,
// calling foo() three times should cause the value of a to increment by 3
void main() {
    foo();
    foo();
    foo();
}

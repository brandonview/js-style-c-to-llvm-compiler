// A function can access global variables

int a;
a = 4;

int foo() {
    a = a * a;
    return a;
}

// However, if a function reinitializes a variable with the global's name, it'll be reinitialized in a local scope
int bar() {
    int a;
    a = 1;
    return a;
}

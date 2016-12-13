// A nested function should have access to the variables in the outer function

int foo() {
    int a;
    a = 0;

    void bar() {
        a = a + 1;
    }

    // This should modify the var a declared on line 4
    bar();

    return a;
}

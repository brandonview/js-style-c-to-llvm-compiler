// A nested function should have access to the variables in the outer function
// However,

int foo() {
    int a;
    a = 0;

    void bar(int b) {
        a = a + 1;
        // once we declare a in local scope, we can't access the inherited function
        int a;
        a = 33;
    }

    // This should modify the var a declared on line 4
    bar(0);

    return a;
}


// Let's test even further function nesting
int foo2() {
    int a;

    void bar2() {
        int b;

        void another() {
            b = b + 1;
            a = a + b;
        }

        another();
    }

    bar2();

    return a;
}

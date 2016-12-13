// NOTE: I am still deciding if this is the best way to allow closures with C syntax
//
// A version of closures implemented on top of our miniCToLlvm compiler

int foo() {
    int a;
    a = 0;

    int bar() {
        a = a + 1;
        return a;
    }

    return a;
}

foo();
foo();
foo();

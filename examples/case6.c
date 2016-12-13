// NOTE: I am still deciding if this is the best way to allow closures with C syntax
//
// A version of closures implemented on top of our miniCToLlvm compiler

function foo() {
    int a;
    a = 0;

    int bar() {
        a = a + 1;
        return a;
    }

    return bar;
}

void main() {
    // creates a function "test" set equal to the return value of "foo",
    // which in this case, is the function "bar"
    function test = foo();

    int testValue;

    testValue = test();
    // testValue = 1 at this point
    testValue = test();
    // testValue = 2 at this point
}

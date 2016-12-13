// NOTE: I am still considering alternate implementations

// Case to demonstrate callback functions

void foo(int a) {
    a = a + 1;
}

// function bar takes a callback function as an arg specified by the "function" keyword
// Think of this as something like "forEach" but for only one value not an array
void bar(function f, x) {
    f(x);
}

int y;
y = 0;
// calling bar() should invoke function foo() on var y 
bar(foo, y);
   

// Case that demonstrates callback functions combined with closure functionality

int foo(int b) {
    int a;
    a = 0;

    int bar(int b) {
        a = a + b;
        return a;
    }

    return bar(b);
}

void baz(function f, int c) {
    c = f(c);
}

void main() {
    int x;
    x = 1;

    baz(foo, x);            // a = 1, x = 1
    baz(foo, x);            // a = 2, x = 2
    baz(foo, x);            // a = 4, x = 4
}

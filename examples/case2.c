// A function can access global variables

int a;
a = 4;

int foo() {
    int a;
    return a * a;
}

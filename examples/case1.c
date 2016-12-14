// A function can access all variables defined _inside_ the function

int foo() {
    struct {
        int x;
        int y;
    } test;
    int a;
    a = 4;
    return a * a;
}

// Declaring a variable inside a function will cause it to be reinitialized every time

void add() {
    int a;
    a = 0;

    a = a + 1;
}

void main() {
    // We should see a distinct value created for the inner var "a" using alloca for each of these calls
    add();
    add();
    add();
}


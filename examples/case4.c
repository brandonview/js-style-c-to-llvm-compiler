// Declaring a variable inside a function will cause it to be reinitialized every time

void add() {
    int a;
    a = 0;

    a = a + 1;
}

// We should see a distinct llvm variable created for the inner var a for each of these calls
add();
add();
add();


// T5 nested when statements
int a = 1
int b = 2
when:
    a == 1:
        when:
            b == 2: output 12
            else: output 10
    else: output 0

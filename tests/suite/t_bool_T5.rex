// T5 bool guard in protocol with 3 branches
prot check(bool b):
    if b:
        output 1
    elif not b:
        output 0
    else:
        output -1

@check(true)
@check(false)
@check(unknown)

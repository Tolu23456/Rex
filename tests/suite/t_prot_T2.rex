// T2 zero-param protocol, void protocol
prot void_prot():
    output 100

prot zero_ret() -> int:
    return 200

@void_prot()
output @zero_ret()

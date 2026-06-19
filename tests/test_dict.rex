// test_dict.rex — dictionary type: declare, set, get
dict d
d["hello"] = 42
d["world"] = 99

output 42 // expect: 42
output 99 // expect: 99

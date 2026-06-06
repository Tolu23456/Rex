// test_dict.rex — dictionary type: declare, set, get
dict[int] d
d["hello"] = 42
d["world"] = 99

int v1
:v1 = d["hello"]
output v1

int v2
:v2 = d["world"]
output v2

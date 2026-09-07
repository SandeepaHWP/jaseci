def use(items: list[any]) -> str {
    tag = "";
    for item in items {
        if item == "x" {
            tag = item;
        }
    }
    return tag;
}

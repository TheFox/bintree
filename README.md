# bintree

A program written in Zig that represents binary data as a tree structure. It helps to explore and understand raw binary formats by displaying the data in a hierarchical, readable form.

## Project Outlines

The project outlines as described in my blog post about [Open Source Software Collaboration](https://blog.fox21.at/2019/02/21/open-source-software-collaboration.html).

- The one and only purpose of this software is to represents binary data in the terminal, command-line.

## Dev

```bash
zig run -freference-trace=12 src/main.zig -- -mh -f tmp/test1.txt -vv -r s01
zig test src/xpath.zig --test-filter simple_xpath
```

```
02FFABCD      /s02/sFF
02                      select 0x02
  FF                    select 0xFF

02FFFFFF      /s02/g3
02                      select 0x02
  FFFFFF                group next 3 bytes

02FFABCD      /s02i2sAB
02                      select 0x02
  FFAB                  ignore next 2 bytes
      CD                select 0xCD

02FFABCD      /.
02                      select any byte

02FFABCD      /..
02                      select any byte
02FF                    select any byte

02FFABCD      /./.
02
  FF

02FFABCD      /./..
02
  FFAB
```

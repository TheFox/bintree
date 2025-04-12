# bintree

## Dev

```bash
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

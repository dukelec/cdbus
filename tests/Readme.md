
Copy test cases from 8-bit branch first:
```
git checkout master test_*.py
git restore --staged test_*.py
```

Then, run `./test_all.sh` or `./test_all.sh test_xxx.py`


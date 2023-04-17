
Copy test cases from master branch first:
```
git checkout master test_*.py
git restore --staged test_*.py
```

Comment out line 66 of `test_break_tx_rx.py`: `#await FallingEdge(dut.irq2)`

Then, run `./test_all.sh` or `./test_all.sh test_xxx.py`


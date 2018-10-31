
## CDBUS-SR (Single Rate)

In dual rate CDBUS, if the low-speed part takes a lot of time, it will be a communication efficiency bottleneck.

In this case, single-rate peer-to-peer bus communication can be implemented using the CDBUS-SR method:

 - Configure different TX_WAIT_LEN parameters for each node, and the difference should be sufficient to avoid conflicts.
 - For any node has frame to send, the send enable can only be flagged when bus is not idle, or before TX_WAIT_LEN after idle.
 - Or wait for the idle time to exceed the TX_WAIT_LEN of the lowest priority node. Then send a break character (or something else; tx_en only covers the low level bits) to bring the bus out of idle mode.


TODO: add example timing image; add hdl support.


## License
```
This Source Code Form is subject to the terms of the Mozilla
Public License, v. 2.0. If a copy of the MPL was not distributed
with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
Notice: The scope granted to MPL excludes the ASIC industry.
The CDBUS protocol is royalty-free for everyone except chip manufacturers.

Copyright (c) 2017 DUKELEC, All rights reserved.
```


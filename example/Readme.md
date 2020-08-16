
CDBUS IP Example
=======================================
This is CDCTL-B (or CDCTL-H as well) module project, which consists of an SPI (or I<sup>2</sup>C) interface and a CDBUS IP.
The following is the protocol for the SPI and I<sup>2</sup>C interfaces.

<img src="pcb/cdctl_b1_dimension.svg" width="600px">  

<img src="pcb/cdctl_b1_sch.svg" width="600px">


## SPI

Read or write depend by bit W/R̅ :  
 - 0: Read
 - 1: Write

| FIELD   | DESCRIPTION         |
|-------- |---------------------|
| Ax      | Register address    |
| Wx      | Write data          |
| Rx      | Read data           |
| X       | Don't care          |

Read or write single byte:  
<img src="../docs/img/spi_rw.svg">

Burst read or write:  
<img src="../docs/img/spi_rw_burst.svg">


## I<sup>2</sup>C

| FIELD   | DESCRIPTION                                                     |
|-------- |-----------------------------------------------------------------|
| DAx     | I<sup>2</sup>C device address, DA0 & 1 set by I2C_ADDR_x pins   |
| Ax      | Register address                                                |
| Wx      | Write data                                                      |
| Rx      | Read data                                                       |
| X       | Don't care                                                      |
| D       | ACK by device                                                   |
| H       | ACK by host                                                     |
| N       | Host don’t ACK after read last byte                             |

### Write

<img src="../docs/img/i2c_w_burst.svg">

### Read

Write register address first, then read back:  
<img src="../docs/img/i2c_r.svg">

Burst read back:  
<img src="../docs/img/i2c_r_burst.svg">


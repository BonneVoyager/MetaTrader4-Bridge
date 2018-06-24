# MetaTrader 4 Bridge

This projects create a request/reply communication layer between [MetaTrader 4](https://www.metatrader4.com/) and your application.

The communication is currently exchanged with [ZeroMQ](http://zeromq.org/) (this could be extended to support more protocols in the future).

A message parser is implemented to make message interpretation task easier to handle.

Parsed messages create bindings for account info, accounts orders and orders management.

## Libraries

* [node-mt4-zmq-bridge](https://github.com/bonnevoyager/node-mt4-zmq-bridge) node.js library.

## Installation

This projects depend on [mql-zmq](https://github.com/dingmaotu/mql-zmq). Install it first.

Then copy MetaTrader4Bridge.mq4 from this projects to Experts folder and compile it in MetaEditor.

Enable Auto Trading in your MetaTrader 4 client application.

## Usage

Add MetaTrader4Bridge Expert Advisor to your chart.

Enable "Allow live trading" and "Allow DLL imports" in Common tab.

Then configure the server in Inputs tab for your needs.

### Two servers

There are two servers which should start along with Expert Advisor. First is REP server and second is PUSH server. The client should subscribe to those servers as REQ and PULL (respectively).

REP server serves the purpose of accepting the messages.

PUSH server is used to send the messages, as well as push data update events (symbol rates, account info, orders change) to the client.

## Protocol

The protocol assumes that request/response messages are strings separated with pipe `|` character ([string split](https://en.wikipedia.org/wiki/Comparison_of_programming_languages_(string_functions)#split)).

## Request

First value from request message is always an id of the request.

Second value is the id of a request type.

Request types are:

| REQUEST_TYPE                       | ID     | Description    |
| :--------------------------------- | :----- | :------------- |
| `REQUEST_PING`                     | `1`    | Ping MT4 client. |
| `REQUEST_TRADE_OPEN`               | `11`   | Create new order. |
| `REQUEST_TRADE_MODIFY`             | `12`   | Modify placed order. |
| `REQUEST_TRADE_DELETE`             | `13`   | Delete pending order. |
| `REQUEST_DELETE_ALL_PENDING_ORDERS`| `21`   | Delete all pending orders. |
| `REQUEST_CLOSE_MARKET_ORDER`       | `22`   | Close open market orders. |
| `REQUEST_CLOSE_ALL_MARKET_ORDERS`  | `23`   | Close all open market orders. |
| `REQUEST_RATES`                    | `31`   | Get current rate for the symbol. |
| `REQUEST_ACCOUNT`                  | `41`   | Get account info. |
| `REQUEST_ORDERS`                   | `51`   | Get account orders. |

Please see the [API](#api) section for detailed description and list of arguments of request types.

#### Example requests

Modify an order.

```
1|12|140602286|108.252|107.525|109.102
```

Delete pending order.

```
2|13|140602286
```

Get current rates for USDJPY.

```
2|31|USDJPY
```

## Response

First value from response message is always an id of the request.

Second value is the id of response status.

Response statuses are:

| RESPONSE_STATUS   | ID  | Description    |
| :---------------- | :-- | :------------- |
| `RESPONSE_OK`     | `0` | Response is successful. |
| `RESPONSE_FAILED` | `1` | Response has failed. |

### Success response

In case of success, rest of the values are response values.

##### Example response

```
2|0|108.926000|108.947000|USDJPY
```

First value `2` is request id. Second value `0` tells us that the response from the server is successful and rest of the message `108.926000|108.947000|USDJPY` can be parsed according to request type.

### Failure response

In case of failure, third value indicates [error code](https://book.mql4.com/appendix/errors). No more values are returned.

###### Example

```
2|1|134
```

First value `2` is request id. Second value `1` indicates that the response from the server has failed and the third value is error code of `134` which means "[Free margin is insufficient](https://book.mql4.com/appendix/errors)".

### Handling request ids

Request id should be unique with every request (e.g. incremented int).

But there are cases in which you might want to use static values, like "ACCOUNT" - which could periodically send account info to the client so it can have up to date data about the account.

## Trade operations

[Trade operations](https://docs.mql4.com/constants/tradingconstants/orderproperties) for opening market order and placing pending order requests.

Operations are:

| OPERATION_TYPE  | ID  | Description    |
| :-------------- | :-- | :------------- |
| `OP_BUY`        | `0` | Buy operation. |
| `OP_SELL`.      | `1` | Sell operation. |
| `OP_BUYLIMIT `  | `2` | Buy limit pending order. |
| `OP_SELLLIMIT ` | `3` | Sell limit pending order. |
| `OP_BUYSTOP `   | `4` | Buy stop pending order. |
| `OP_SELLSTOP `  | `5` | Sell stop pending order. |

## Unit types

Unit types for order volume management requests.

Unit types are:

| UNIT_TYPE        | ID  | Description    |
| :--------------- | :-- | :------------- |
| `UNIT_CONTRACTS` | `0` | Use contracts volume unit. |
| `UNIT_CURRENCY`  | `1` | Use currency volume unit. |

For `0` `UNIT_CONTRACTS` no additional calculations are performed, so the volume is unchanged.

For `1` `UNIT_CURRENCY` the volume specified for the trade is divided by the result price.

##### Example

Let's assume that we place two orders for `USDJPY` with volume `10` price `110` and two different unit types of `0` and `1`.

In case of order with unit `0`, then the volume will stay at `10`.

In case of order with unit `1`, then the volume of `10` will be divided by the price `110`, resulting with the final volume of ~`0.0909`.

## Price modificators

Price modificator are used to undercut or overcut the price value.

Price modificators are:

| MODIFICATOR_TYPE | Description | Example |
| :--------------- | :------------- | :------------- |
| `-`              | Undercut market price by specified value. | `-5` |
| `+`              | Overcut market price by specified value. | `+10` |
| `%`              | Undercut/overcut market price by specified percentage. | `-15%`, `+20%` |

If modificator wasn't found (it's always first character in `BASE_PRICE`/`BASE_STOPLOSS`/`BASE_TAKEPROFIT` value), then it's treated as literal value.

##### Examples

Let's assume that the market price is `200` (it's irrelevant if it's bid or ask).

In case of modificator `-5`, the result price will be `195`.

In case of modificator `+10`, the result price will be `210`.

In case of modificator `-15%`, the result price will be `170`.

In case of modificator `+20%`, the result price will be `240`.

In case of literal value `250`, the result price will be `250`.

## API

All listed request values are required.

### [REQUEST\_PING [1]](#request)

Ping MetaTrader 4 Client.

#### Request values

\<none\>

###### Example

```
102|1
```

#### Response values

`TS` current MT4 client timestamp in seconds.

###### Example

```
102|0|140602286
```

### [REQUEST\_TRADE\_OPEN [11]](#request)

Open an order.

Key function from MT4 client used for this request is [OrderSend](https://docs.mql4.com/trading/ordersend).

#### Request values

`SYMBOL` (string) symbol for trading.  
`OPERATION` (int) [operation type](#trade-operations).   
`VOLUME` (double | string) trade volume.   
`BASE_PRICE` (double) literal value or [modificator](#price-modificators) for order price.  
`SLIPPAGE` (int) maximum price slippage for buy or sell orders.  
`BASE_STOPLOSS` (double | string) literal value or [modificator](#price-modificators) for stop loss level.  
`BASE_TAKEPROFIT` (double | string) literal value or [modificator](#price-modificators) for take profit level.  
`COMMENT` (string) order comment text. Limit is 27 characters. Do not use pipe `|`. Can be empty.  
`MAGIC_NUMBER` (int) order magic number. May be used as user defined identifier.  
`UNIT` (int) [unit type](#unit-types).

###### Example

```
236|11|USDJPY|2|1|108.848|0|0|0|comment message goes here|123|0
```

#### Response values

`TICKET` order ticket received from trade server.

###### Example

```
236|0|140602286
```

### [REQUEST\_TRADE\_MODIFY [12]](#request)

Modify an order.

Key function from MT4 client used for this request is [OrderModify](https://docs.mql4.com/trading/ordermodify).

#### Request values

`TICKET` (int) order ticket.  
`BASE_PRICE` (double | string) literal value or [modificator](#price-modificators) for order price.  
`BASE_STOPLOSS` (double | string) literal value or [modificator](#price-modificators) for stop loss level.  
`BASE_TAKEPROFIT` (double | string) literal value or [modificator](#price-modificators) for take profit level.

###### Example

```
312|12|140602286|108.252|107.525|109.102
```

#### Response values

`TICKET` order ticket.

###### Example

```
312|0|140602286
```

### [REQUEST\_TRADE\_DELETE [13]](#request)

Delete pending order.

Key function from MT4 client used for this request is [OrderDelete](https://docs.mql4.com/trading/orderdelete).

#### Request values

`TICKET` (int) pending order ticket.

###### Example

```
318|13|140602286
```

#### Response values

`TICKET` order ticket.

###### Example

```
318|0|140602286
```

### [REQUEST\_DELETE\_ALL\_PENDING\_ORDERS [21]](#request)

Delete all pending orders.

#### Request values

`SYMBOL` (string) symbol for which pending orders should be deleted.

###### Example

```
345|21|USDJPY
```

#### Response values

`DELETED_COUNT` number of deleted pending orders.

###### Example

```
345|0|2
```

### [REQUEST\_CLOSE\_MARKET\_ORDER [22]](#request)

Close market order.

Key function from MT4 client used for this request is [OrderClose](https://docs.mql4.com/trading/orderclose).

#### Request values

`TICKET` (int) market order ticket.

###### Example

```
380|22|140612332
```

#### Response values

`TICKET` order ticket.

###### Example

```
380|0|140612332
```

### [REQUEST\_CLOSE\_ALL\_MARKET\_ORDERS [23]](#request)

Close all market orders.

#### Request values

`SYMBOL` (string) symbol for which market orders should be closed.

###### Example

```
383|23|USDJPY
```

#### Response values

`DELETED_COUNT` number of deleted pending orders.

###### Example

```
383|0|3
```

### [MSG\_RATES [31]](#request)

Get current rates for requested symbol.

#### Request values

`SYMBOL` (string)

###### Example

```
397|31|USDJPY
```

#### Response values

`BID` current bid price.  
`ASK` current ask price.  
`SYMBOL` the symbol.

###### Example

```
397|0|108.926000|108.947000|USDJPY
```

### [REQUEST\_ACCOUNT [41]](#request)

Get account info.

#### Request values

\<none\>

###### Example

```
415|41
```

#### Response values

`CURRENCY` account currency.  
`BALANCE` account balance in the deposit currency.  
`PROFIT` current profit of an account in the deposit currency.  
`EQUITY_MARGIN` account equity in the deposit currency.  
`MARGIN_FREE` free margin of an account in the deposit currency.  
`MARGIN_LEVEL` account margin level in percents.  
`MARGIN_SO_CALL` margin call level.  
`MARGIN_SO_SO` margin stop out level.

###### Example

```
415|0|USD|10227.43|-129.46|10097.97|4000.00|6097.97|252.45|50.00|20.00
```

### [REQUEST\_ORDERS [51]](#request)

Get account orders.

In this specific case, order values are separated by comma `,` and orders are separated by pipe `|`. So after splitting the response, you will have the orders which you would probably need to split again with `,` as a separator (e.g. `response.split('|').map(item => item.split(','))`).

#### Request values

\<none\>

###### Example

```
467|51
```

#### Response values

`ORDERS` orders with values separated by comma `,`.  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`TICKET` order ticket.  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`OPEN_TIME` order open price.  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`TYPE` [order type](#trade-operations).  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LOTS` order volume.  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`SYMBOL` order symbol.  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`OPEN_PRICE` order open price.

###### Example

```
467|0|140617577,2018.05.31 10:40,1,0.01,EURUSD,1.17017,|140623054,2018.05.31 14:20,3,0.11,USDJPY,130.72600,
```

## Changelog

[CHANGELOG.md](https://github.com/BonneVoyager/MetaTrader4-Bridge/blob/master/CHANGELOG.md)

## License

MIT

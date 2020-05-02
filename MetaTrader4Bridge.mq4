//+------------------------------------------------------------------+
//|                                            MetaTrader4Bridge.mq4 |
//|                                     Copyright 2020, bonnevoyager |
//|               https://github.com/bonnevoyager/MetaTrader4-Bridge |
//|  This file DOES NOT come with ANY warranty, use at YOUR OWN risk |
//+------------------------------------------------------------------+
#property copyright "Copyright 2020, bonnevoyager."
#property version   "1.2"
#property strict

// Required: MQL-ZMQ from https://github.com/dingmaotu/mql-zmq
#include <Zmq/Zmq.mqh>

extern string PROJECT_NAME = "MetaTrader 4 Bridge";
extern string ZEROMQ_PROTOCOL = "tcp";
extern string HOSTNAME = "*";
extern int REP_PORT = 5555;
extern int PUSH_PORT = 5556;

// ZeroMQ Context
Context context(PROJECT_NAME);

// ZMQ_REP SOCKET
Socket repSocket(context, ZMQ_REP);

// ZMQ_PUSH SOCKET
Socket pushSocket(context, ZMQ_PUSH);

//--- VARIABLES FOR LATER
uchar mdata[];
ZmqMsg request;
bool runningTests;

//--- UPDATE VARIABLES
int lastUpdateSeconds;
string lastUpdateRates;
string lastUpdateAccount;
string lastUpdateOrders;

//--- REQUEST TYPES
int REQUEST_PING = 1;
int REQUEST_TRADE_OPEN = 11;
int REQUEST_TRADE_MODIFY = 12;
int REQUEST_TRADE_DELETE = 13;
int REQUEST_DELETE_ALL_PENDING_ORDERS = 21;
int REQUEST_CLOSE_MARKET_ORDER = 22;
int REQUEST_CLOSE_ALL_MARKET_ORDERS = 23;
int REQUEST_RATES = 31;
int REQUEST_ACCOUNT = 41;
int REQUEST_ORDERS = 51;

//--- RESPONSE STATUSES
int RESPONSE_OK = 0;
int RESPONSE_FAILED = 1;

//--- UNIT TYPES
int UNIT_CONTRACTS = 0;
int UNIT_CURRENCY = 1;

//+------------------------------------------------------------------+
//| Expert initialization function.                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   /*
      Perform core system check.
   */
   if (!RunTests())
   {
      return(INIT_FAILED);
   }

   EventSetMillisecondTimer(1);  // Set Millisecond Timer to get client socket input
   
   PrintFormat("[REP] Binding MT4 Server to Socket on Port %d.", REP_PORT);   
   PrintFormat("[PUSH] Binding MT4 Server to Socket on Port %d.", PUSH_PORT);
   
   repSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, REP_PORT));
   pushSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT));
   
   /*
       Maximum amount of time in milliseconds that the thread will try to send messages 
       after its socket has been closed (the default value of -1 means to linger forever):
   */
   
   repSocket.setLinger(1000);  // 1000 milliseconds
   
   /* 
      If we initiate socket.send() without having a corresponding socket draining the queue, 
      we'll eat up memory as the socket just keeps enqueueing messages.
      
      So how many messages do we want ZeroMQ to buffer in RAM before blocking the socket?
   */
   
   repSocket.setSendHighWaterMark(10);  // 10 messages only.

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function.                                |
//+------------------------------------------------------------------+
void OnDeinit(
   const int reason
) {
   PrintFormat("[REP] Unbinding MT4 Server from Socket on Port %d.", REP_PORT);
   repSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, REP_PORT));
   
   PrintFormat("[PUSH] Unbinding MT4 Server from Socket on Port %d.", PUSH_PORT);
   pushSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT));
}

//+------------------------------------------------------------------+
//| Expert timer function.                                           |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Get client's response, but don't wait.
   repSocket.recv(request, true);
  
   // Send response to the client.
   ZmqMsg reply = MessageHandler(request);
   repSocket.send(reply);
   
   // Send periodical updates to connected sockets.
   SendUpdateMessage(pushSocket);
}

//+------------------------------------------------------------------+
//| Send Status Update data to the Client.                           |
//+------------------------------------------------------------------+
void SendUpdateMessage(
   Socket &pSocket
) {
   int seconds = TimeSeconds(TimeCurrent());

   // Update every second.
   if (lastUpdateSeconds != seconds)
   {
      lastUpdateSeconds = seconds;
      
      // Send rates update (if they changed).
      /*string ratesInfoString = GetRatesString("EURUSD");
      if (lastUpdateRates != ratesInfoString)
      {
         lastUpdateRates = ratesInfoString;
         InformPullClient(pSocket, "RATES", ratesInfoString);
      }*/
      
      // Send account update (if it changed).
      string accountInfoString = GetAccountInfoString();
      if (lastUpdateAccount != accountInfoString)
      {
         lastUpdateAccount = accountInfoString;
         InformPullClient(pSocket, "ACCOUNT", accountInfoString);
      }
      
      // Send orders list update (if it changed).
      string ordersInfoString = GetAccountOrdersString();
      if (lastUpdateOrders != ordersInfoString)
      {
         lastUpdateOrders = ordersInfoString;
         InformPullClient(pSocket, "ORDERS", ordersInfoString);
      }
   }
}

//+------------------------------------------------------------------+
//| Handle request message.                                          |
//+------------------------------------------------------------------+
ZmqMsg MessageHandler(
   ZmqMsg &rRequest
) {
   // Output object.
   ZmqMsg reply;
   
   // Message components for later.
   string components[];
   
   if (request.size() > 0)
   {
      // Get data from request.
      ArrayResize(mdata, request.size());
      request.getData(mdata);
      string dataStr = CharArrayToString(mdata);
      
      // Process data.
      ParseZmqMessage(dataStr, components);
      
      // Interpret data.
      InterpretZmqMessage(pushSocket, components);
      
      // Construct response.
      string id = components[0];
      ZmqMsg ret(id);
      reply = ret;
   }
   
   return(reply);
}

//+------------------------------------------------------------------+
//| Parse Zmq Message received from the client.                      |
//| A message should be a string with values separated by pipe sign. |
//| Example: 2|31|EURUSD                                             |
//+------------------------------------------------------------------+
void ParseZmqMessage(
   string& message,
   string& retArray[]
) {
   PrintFormat("Parsing: %s", message);
   
   string sep = "|";
   ushort u_sep = StringGetCharacter(sep, 0);
   
   StringSplit(message, u_sep, retArray);
}

//+------------------------------------------------------------------+
//| Send a message to the client.                                    |
//+------------------------------------------------------------------+
void InformPullClient(
   Socket& pSocket,
   string  message_id,
   string  message
) {
   ZmqMsg pushReply(StringFormat("%s|%s", message_id, message));
   // pushSocket.send(pushReply,true,false);
   
   pSocket.send(pushReply, true);                // NON-BLOCKING
   // targetSocket.send(pushReply,false);           // BLOCKING
}

//+------------------------------------------------------------------+
//| Checks whether the program is operational.                       |
//+------------------------------------------------------------------+
int RunTests()
{
   int testsNotPassed = 0;
   
   runningTests = true;
   
   // Checking for Permission to Perform Automated Trading
   if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
      testsNotPassed += 1;
      
   ///Checking for Permission to Perform Automated Trading for this program
   if (!MQLInfoInteger(MQL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_DLLS_ALLOWED))
      testsNotPassed += 2;
      
   // Checking if trading is allowed for any Expert Advisors/scripts for the current account
   if (!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      testsNotPassed += 4;
      
   // Checking if trading is allowed for the current account
   if (!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      testsNotPassed += 8;
   
   // Should NOT ALLOW open price modification for market orders and pending orders out of freeze level range.
   if (HasValidFreezeAndStopLevels("USDJPY", OP_BUY, Bid - 0.1, Bid, Bid - 0.3, Bid + 0.3) != -1 ||
      HasValidFreezeAndStopLevels("USDJPY", OP_SELL, Ask + 0.1, Ask, Ask + 0.3, Ask - 0.3) != -1 ||
      HasValidFreezeAndStopLevels("USDJPY", OP_BUYLIMIT, Bid - 0.1, Bid, Bid - 0.3, Bid + 0.3) != -2 ||
      HasValidFreezeAndStopLevels("USDJPY", OP_SELLLIMIT, Ask + 0.1, Ask, Ask + 0.3, Ask - 0.3) != -2 ||
      HasValidFreezeAndStopLevels("USDJPY", OP_BUYSTOP, Ask - 0.1, Ask + 0.1, Ask + 0.3, Ask + 0.3) != -2 ||
      HasValidFreezeAndStopLevels("USDJPY", OP_SELLSTOP, Bid + 0.1, Bid - 0.1, Bid - 0.3, Bid - 0.5) != -2)
      testsNotPassed += 16;
   
   // Should NOT ALLOW stop loss modification for market orders out of freeze range.
   if (HasValidFreezeAndStopLevels("USDJPY", OP_BUY, 0, Bid, Bid - 0.1, 0) != -3 ||
      HasValidFreezeAndStopLevels("USDJPY", OP_SELL, Ask, Ask, Ask + 0.1, 0)!= -3)
      testsNotPassed += 32;
   
   // Should NOT ALLOW take profit modification for market orders out of freeze range.
   if (HasValidFreezeAndStopLevels("USDJPY", OP_BUY, 0, Bid, 0, Bid + 0.1) != -4 ||
      HasValidFreezeAndStopLevels("USDJPY", OP_SELL, Ask, Ask, 0, Ask - 0.1)!= -4)
      testsNotPassed += 64;
      
   // Should ALLOW open price modification for pending orders.
   if (HasValidFreezeAndStopLevels("USDJPY", OP_BUYLIMIT, Bid - 0.5, Bid - 0.25, Bid - 0.6, Bid + 0.6) != 1 ||
      HasValidFreezeAndStopLevels("USDJPY", OP_SELLLIMIT, Ask + 0.5, Ask + 0.25, Ask + 0.6, Ask - 0.6) != 1 ||
      HasValidFreezeAndStopLevels("USDJPY", OP_BUYSTOP, Ask, Ask + 0.50, Ask + 0.25, Ask + 0.75) != 1 ||
      HasValidFreezeAndStopLevels("USDJPY", OP_SELLSTOP, Bid, Bid - 0.50, Bid - 0.25, Bid - 0.75) != 1)
      testsNotPassed += 128;
      
   // Should calculate correct prices.
   if (CalculateAndNormalizePrice("0", OP_BUY) != Ask ||
      CalculateAndNormalizePrice(DoubleToStr(Ask), OP_BUYLIMIT) != Ask ||
      CalculateAndNormalizePrice("-15", OP_SELLLIMIT) != Bid - 15 ||
      CalculateAndNormalizePrice("+10", OP_BUYLIMIT) != Ask + 10 ||
      CalculateAndNormalizePrice("%+10", OP_BUYLIMIT) != NormalizeDouble(Ask * 1.1, Digits) ||
      CalculateAndNormalizePrice("%-15", OP_BUYLIMIT) != NormalizeDouble(Ask * 0.85, Digits))
      testsNotPassed += 256;
      
   runningTests = false;

   if (testsNotPassed)
   {
      PrintFormat("Tests didn't pass with %d!", testsNotPassed);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check order against exchange freeze and stop levels.             |
//|  1 - trade has valid open price and SL/TP.                       |
//| -1 - open price modification is not allowed.                     |
//| -2 - open price is out of freeze level range.                    |
//| -3 - stop loss is out of freeze level range.                     |
//| -4 - take profit is out of freeze level range.                   |
//| -5 - open price is out of stop level range.                      |
//| -6 - stop loss is out of stop level range.                       |
//| -7 - take profit is out of stop level range.                     |
//+------------------------------------------------------------------+
int HasValidFreezeAndStopLevels(
   string symbol,
   int    cmd,
   double openPrice,
   double price,
   double stoploss,
   double takeprofit
) {
   double FreezeLevel = runningTests ? 0.2 : MarketInfo(symbol, MODE_FREEZELEVEL);
   double StopLevel = runningTests ? 0.2 : MarketInfo(symbol, MODE_STOPLEVEL);
   
   if (openPrice != price)                       // Check open price modification
   {
      if (openPrice && (cmd == OP_BUY || cmd == OP_SELL))
      {                                          // Check if market order
         return(-1);
      }
      else if (                                  // Check freeze level
         (cmd == OP_BUYLIMIT && Ask - price <= FreezeLevel) ||
         (cmd == OP_SELLLIMIT && price - Bid <= FreezeLevel) ||
         (cmd == OP_BUYSTOP && price - Ask <= FreezeLevel) ||
         (cmd == OP_SELLSTOP && Bid - price <= FreezeLevel)
      ) {
         return(-2);
      }
      else if (                                  // Check stop level
         (cmd == OP_BUYLIMIT && Ask - price < StopLevel) ||
         (cmd == OP_SELLLIMIT && price - Bid < StopLevel) ||
         (cmd == OP_BUYSTOP && price - Ask < StopLevel) ||
         (cmd == OP_SELLSTOP && Bid - price < StopLevel)
      )
      {
         return(-5);
      }
   }
   
   if (stoploss)                                 // Check stop loss
   {
      if (                                       // Check freeze level
         (cmd == OP_BUY && Bid - stoploss <= FreezeLevel) ||
         (cmd == OP_SELL && stoploss - Ask <= FreezeLevel)
      ) {
         return(-3);
      }
      else if (                                  // Check stop level
         (cmd == OP_BUY && Bid - stoploss < StopLevel) ||
         (cmd == OP_SELL && stoploss - Ask < StopLevel) ||
         (cmd == OP_BUYLIMIT && price - stoploss < StopLevel) ||
         (cmd == OP_SELLLIMIT && stoploss - price < StopLevel) ||
         (cmd == OP_BUYSTOP && price - stoploss < StopLevel) ||
         (cmd == OP_SELLSTOP && stoploss - price < StopLevel)
      )
      {
         return(-6);
      }
   }
   
   if (takeprofit)                               // Check take profit
   {
      if (                                       // Check freeze level
         (cmd == OP_BUY && takeprofit - Bid <= FreezeLevel) ||
         (cmd == OP_SELL && Ask - takeprofit <= FreezeLevel)
      ) {
         return(-4);
      }
      else if (                                  // Check stop level
         (cmd == OP_BUY && takeprofit - Bid < StopLevel) ||
         (cmd == OP_SELL && Ask - takeprofit < StopLevel) ||
         (cmd == OP_BUYLIMIT && takeprofit - price < StopLevel) ||
         (cmd == OP_SELLLIMIT && price - takeprofit < StopLevel) ||
         (cmd == OP_BUYSTOP && takeprofit - price < StopLevel) ||
         (cmd == OP_SELLSTOP && price - takeprofit < StopLevel)
      )
      {
         return(-7);
      }
   }
   
   return(1);
}

//+------------------------------------------------------------------+
//| Apply optional modifier and normalize the price.                 |
//| Possible modifiers are:                                          |
//|  - - reduce base or market price by given value                  |
//|  + - increase base or market price by given value                |
//|  % - percentage multiplier of base or market price               |
//+------------------------------------------------------------------+
double CalculateAndNormalizePrice(
   string basePrice,
   int    cmd
) {
   RefreshRates();

   double price;
   double marketPrice = cmd % 2 == 1 ? Bid : Ask;
   
   if (cmd != -1 && (cmd < 2 || basePrice == "0")) // Use market price
   {
      price = marketPrice;
   }
   else if (cmd == -1 && basePrice == "0")         // Use empty value
   {
      price = 0;
   }
   else
   {
      string modifier = StringSubstr(basePrice, 0, 1);
      if (modifier == "-")                           // Undercut modifier
      {
         price = marketPrice + StrToDouble(basePrice);
      }
      else if (modifier == "+")                      // Overcut modifier
      {
         price = marketPrice + StrToDouble(StringSubstr(basePrice, 1));
      }
      else if (modifier == "%")                      // Percentage modifier
      {
         price = marketPrice * (1 + (StrToDouble(StringSubstr(basePrice, 1))) / 100);
      }
      else                                           // Apply no modifier
      {
         price = StrToDouble(basePrice);
      }
      
      price = NormalizeDouble(price, Digits);
   }

   return(price);
}

//+------------------------------------------------------------------+
//| Check the trade context status. Return codes:                    |
//|  1 - trade context is free, trade allowed.                       |
//|  0 - trade context was busy, but became free. Trade is allowed   |
//|      only after the market info has been refreshed.              |
//| -1 - trade context is busy, waiting interrupted by the user      |
//|      (expert was removed from the chart, terminal was shut down, |
//|      the chart period and/or symbol was changed, etc.).          |
//| -2 - trade context is busy, waiting limit is reached (waitFor).  |
//+------------------------------------------------------------------+
int IsAllowedToTrade(
   int waitFor = 15
) {
   // check whether the trade context is free
   if (!IsTradeAllowed())
   {
      int StartWaitingTime = (int)GetTickCount();

      // infinite loop
      while (true)
      {
         // if the expert was terminated by the user, stop operation
         if (IsStopped()) 
         { 
            Alert("The expert was terminated by the user!"); 
            return(-1); 
         }
         // if the waiting time exceeds the time specified in the 
         // MaxWaiting_sec variable, stop operation, as well
         if ((int)GetTickCount() - StartWaitingTime > waitFor * 1000)
         {
            Alert(StringFormat("The waiting limit exceeded (%d seconds)!", waitFor));
            return(-2);
         }
         // if the trade context has become free,
         if (IsTradeAllowed())
         {
            return(0);
         }
         // if no loop breaking condition has been met, "wait" for 0.1 
         // second and then restart checking
         Sleep(100);
      }
   }
   else
   {
      return(1);
   }
}

//+------------------------------------------------------------------+
//| Interpret Zmq Message validate it and perform an action.         |
//+------------------------------------------------------------------+
void InterpretZmqMessage(
   Socket& pSocket,
   string& compArray[]
) {
   // Pull data string.
   string response = "";
   
   // Message id and type of a message.
   string id = compArray[0];
   int type = (int)compArray[1];
   
   if (type == REQUEST_PING)
   {
      response = StringFormat("%d|%d", RESPONSE_OK, TimeLocal());
   }
   else if (type == REQUEST_TRADE_OPEN)
   {
      if (ArraySize(compArray) != 12)
      {
         response = StringFormat("%d|4050", RESPONSE_FAILED);
      }
      else
      {
         string symbol = compArray[2];
         int operation = (int)compArray[3];
         double volume = (double)compArray[4];
         string basePrice = compArray[5];
         int slippage = (int)compArray[6];
         string baseStoploss = compArray[7];
         string baseTakeprofit = compArray[8];
         string comment = compArray[9];
         int magicnumber = (int)compArray[10];
         int unit = (int)compArray[11];
         
         response = OpenOrder(symbol, operation, volume, basePrice, slippage, baseStoploss, baseTakeprofit, comment, magicnumber, unit);
      }
   }
   else if (type == REQUEST_TRADE_MODIFY)
   {
      if (ArraySize(compArray) != 6)
      {
         response = StringFormat("%d|4050", RESPONSE_FAILED);
      }
      else
      {
         int ticket = (int)compArray[2];
         string basePrice = compArray[3];
         string baseStoploss = compArray[4];
         string baseTakeprofit = compArray[5];
      
         response = ModifyOrder(ticket, basePrice, baseStoploss, baseTakeprofit);
      }
   }
   else if (type == REQUEST_TRADE_DELETE)
   {
      if (ArraySize(compArray) != 3)
      {
         response = StringFormat("%d|4050", RESPONSE_FAILED);
      }
      else
      {
         int ticket = (int)compArray[2];
   
         response = DeletePendingOrder(ticket);
      }
   }
   else if (type == REQUEST_RATES)
   {
      if (ArraySize(compArray) != 3)
      {
         response = StringFormat("%d|4050", RESPONSE_FAILED);
      }
      else
      {
         string symbol = compArray[2];
   
         response = GetRatesString(symbol);
      }
   }
   else if (type == REQUEST_ACCOUNT)
   {
      response = GetAccountInfoString();
   }
   else if (type == REQUEST_ORDERS)
   {
      response = GetAccountOrdersString();
   }
   else if (type == REQUEST_DELETE_ALL_PENDING_ORDERS)
   {
      if (ArraySize(compArray) != 3)
      {
         response = StringFormat("%d|4050", RESPONSE_FAILED);
      }
      else
      {
         string symbol = compArray[2];
   
         response = DeleteAllPendingOrders(symbol);
      }
   }
   else if (type == REQUEST_CLOSE_MARKET_ORDER)
   {
      if (ArraySize(compArray) != 3)
      {
         response = StringFormat("%d|4050", RESPONSE_FAILED);
      }
      else
      {
         int ticket = (int)compArray[2];
   
         response = CloseMarketOrder(ticket);
      }
   }
   else if (type == REQUEST_CLOSE_ALL_MARKET_ORDERS)
   {
      if (ArraySize(compArray) != 3)
      {
         response = StringFormat("%d|4050", RESPONSE_FAILED);
      }
      else
      {
         string symbol = compArray[2];
   
         response = CloseAllMarketOrders(symbol);
      }
   }
   
   PrintFormat("Response: %s|%s", id, response);
   
   // Send a response.
   InformPullClient(pSocket, id, response);
}

//+------------------------------------------------------------------+
//| Open an order.                                                   |
//| Input:   SYMBOL|OPERATION|VOLUME|BASE_PRICE|SLIPPAGE|            |
//|             BASE_STOPLOSS|BASE_TAKEPROFIT|COMMENT|MAGIC_NUMBER|  |
//|             UNIT                                                 |  
//| Example: USDJPY|2|1|108.848|0|0|0|some text|123|0                |
//| Output:  TICKET                                                  |
//| Example: 140602286                                               |
//+------------------------------------------------------------------+
string OpenOrder(
   string symbol,
   int    cmd,
   double volume,
   string basePrice,
   int    slippage,
   string baseStoploss,
   string baseTakeprofit,
   string comment,
   int    magicnumber,
   int    unit
) {
   while(true)
   {
      double price = CalculateAndNormalizePrice(basePrice, cmd);
      double stoploss = CalculateAndNormalizePrice(baseStoploss, -1);
      double takeprofit = CalculateAndNormalizePrice(baseTakeprofit, -1);
      
      if (unit == UNIT_CURRENCY)
      {
         volume /= price;
      }
      
      if (HasValidFreezeAndStopLevels(symbol, cmd, 0, price, stoploss, takeprofit) < 0)
      {
         return(StringFormat("%d|130", RESPONSE_FAILED)); // Invalid stops
      }
      else if (volume < MarketInfo(symbol, MODE_MINLOT) || volume > MarketInfo(symbol, MODE_MAXLOT))
      {
         return(StringFormat("%d|131", RESPONSE_FAILED)); // Volume below min or above max
      }
      else if (cmd < 2 && (AccountFreeMarginCheck(symbol, cmd, volume) <= 0 || GetLastError() == 134))
      {
         return(StringFormat("%d|134", RESPONSE_FAILED)); // Free margin is insufficient
      }
      else if (IsAllowedToTrade() < 0)
      {
         return(StringFormat("%d|146", RESPONSE_FAILED)); // Trader context is busy
      }
   
      int ticket = OrderSend(symbol, cmd, volume, price, slippage, stoploss, takeprofit, comment, magicnumber, 0, clrGreen);
       
      if (ticket > 0)
      {
         return(StringFormat("%d|%d", RESPONSE_OK, ticket));
      }
      else
      {
         int error = GetLastError();
         
         switch(error)                           // Overcomable errors
         {
            case 4:                              // Trade server is busy. Retrying...
               Sleep(2000);                      // Try again
               continue;                         // At the next iteration
            case 135:                            // The price has changed. Retrying...
               RefreshRates();                   // Update data
               continue;                         // At the next iteration
            case 136:                            // No prices. Waiting for a new tick...
               while(RefreshRates() == false)    // Up to a new tick
                  Sleep(1);                      // Cycle delay
               continue;                         // At the next iteration
            case 137:                            // Broker is busy. Retrying...
               Sleep(2000);                      // Try again
               continue;                         // At the next iteration
            case 146:                            // Trading subsystem is busy. Retrying...
               Sleep(500);                       // Try again
               RefreshRates();                   // Update data
               continue;                         // At the next iteration
            default:
               Alert(StringFormat("OpenOrder error: %d", error));
               return(StringFormat("%d|%d", RESPONSE_FAILED, error));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify an order.                                                 |
//| Input:   TICKET|BASE_PRICE|BASE_STOPLOSS|BASE_TAKEPROFIT         |
//| Example: 140602286|108.252|107.525|109.102                       |
//| Output:  TICKET                                                  |
//| Example: 140602286                                               |
//+------------------------------------------------------------------+
string ModifyOrder(
   int    ticket,
   string basePrice,
   string baseStoploss,
   string baseTakeprofit
) {
   bool success;

   while(true)
   {
      if (OrderSelect(ticket, SELECT_BY_TICKET) == false)
      {
         success = false;
      }
      else
      {
         double openPrice = OrderOpenPrice();
         double price;
         
         if (OrderType() < 2)
         {
            price = openPrice;
         }
         else
         {
            price = CalculateAndNormalizePrice(basePrice, -1);
         }

         double stoploss = CalculateAndNormalizePrice(baseStoploss, -1);
         double takeprofit = CalculateAndNormalizePrice(baseTakeprofit, -1);
         
         if (HasValidFreezeAndStopLevels(OrderSymbol(), OrderType(), openPrice, price, stoploss, takeprofit) < 0)
         {
            return(StringFormat("%d|130", RESPONSE_FAILED)); // Invalid stops
         }
         else if (IsAllowedToTrade() < 0)
         {
            return(StringFormat("%d|146", RESPONSE_FAILED)); // Trader context is busy
         }
         
         success = OrderModify(ticket, price, stoploss, takeprofit, 0, clrGreen);
      }
      
      if (success)
      {
         return(StringFormat("%d|%d", RESPONSE_OK, ticket));
      }
      else
      {
         int error = GetLastError();
         
         switch(error)                           // Overcomable errors
         {
            case 4:                              // Trade server is busy. Retrying...
               Sleep(2000);                      // Try again
               continue;                         // At the next iteration
            case 137:                            // Broker is busy. Retrying...
               Sleep(2000);                      // Try again
               continue;                         // At the next iteration
            case 146:                            // Trading subsystem is busy. Retrying...
               Sleep(500);                       // Try again
               continue;                         // At the next iteration
            default:
               Alert(StringFormat("ModifyOrder error: %d", error));
               return(StringFormat("%d|%d", RESPONSE_FAILED, error));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Delete pending order.                                            |
//| Input:   TICKET                                                  |
//| Example: 140602286                                               |
//| Output:  TICKET                                                  |
//| Example: 140602286                                               |
//+------------------------------------------------------------------+
string DeletePendingOrder(
   int ticket
) {
   bool success;

   while(true)
   {
      if (OrderSelect(ticket, SELECT_BY_TICKET) == false)
      {
         success = false;
      }
      else
      {
         if (IsAllowedToTrade() < 0)
         {
            return(StringFormat("%d|146", RESPONSE_FAILED)); // Trader context is busy
         }
         
         success = OrderDelete(ticket, CLR_NONE);
      }
      
      if (success)
      {
         return(StringFormat("%d|%d", RESPONSE_OK, ticket));   
      }
      else
      {
         int error = GetLastError();
         
         switch(error)                           // Overcomable errors
         {
            case 4:                              // Trade server is busy. Retrying...
               Sleep(2000);                      // Try again
               continue;                         // At the next iteration
            case 137:                            // Broker is busy. Retrying...
               Sleep(2000);                      // Try again
               continue;                         // At the next iteration
            case 146:                            // Trading subsystem is busy. Retrying...
               Sleep(500);                       // Try again
               continue;                         // At the next iteration
            default:
               Alert(StringFormat("DeletePendingOrder error: %d", error));
               return(StringFormat("%d|%d", RESPONSE_FAILED, error));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Delete all pending orders.                                       |
//| Input:   SYMBOL                                                  |
//| Example: USDJPY                                                  |
//| Output:  DELETED_COUNT                                           |
//| Example: 2                                                       |
//+------------------------------------------------------------------+
string DeleteAllPendingOrders(
   string symbol
) {
   int deletedCount = 0;
   
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      bool found = OrderSelect(i, SELECT_BY_POS);
      
      // Order not found or Symbol is not ours.
      if (!found || OrderSymbol() != symbol) continue;
      
      // Select only pending orders.
      if (OrderType() > 1)
      {
         string response = DeletePendingOrder(OrderTicket());
         
         if (StringFind(response, (string)RESPONSE_OK) == 0)
         {
            deletedCount++;
         }
      }
   }
   
   return(StringFormat("%d|%d", RESPONSE_OK, deletedCount));
}

//+------------------------------------------------------------------+
//| Close market order.                                              |
//| Input:   TICKET                                                  |
//| Example: 140612332                                               |
//| Output:  TICKET                                                  |
//| Example: 140612332                                               |
//+------------------------------------------------------------------+
string CloseMarketOrder(
   int ticket
) {
   PrintFormat("ORDER CLOSE #%d", ticket);

   bool success;

   while(true)
   {
      if (OrderSelect(ticket, SELECT_BY_TICKET) == false)
      {
         success = false;
      }
      else
      {
         double price = 0;
         
         switch(OrderType())                     // By order type
         {
            case 0:
               price = Bid;                      // Order Buy
               break;
            case 1:
               price = Ask;                      // Order Sell
               break;
         }
         
         if (IsAllowedToTrade() < 0)
         {
            return(StringFormat("%d|146", RESPONSE_FAILED)); // Trader context is busy
         }
      
         success = OrderClose(ticket, OrderLots(), price, 2, clrRed);
      }
      
      if (success)
      {
         return(StringFormat("%d|%d", RESPONSE_OK, ticket));   
      }
      else
      {
         int error = GetLastError();
         
         switch(error)                           // Overcomable errors
         {
            case 129:                            // Wrong price
            case 135:                            // The price has changed. Retrying...
               RefreshRates();                   // Update data
               continue;                         // At the next iteration
            case 136:                            // No prices. Waiting for a new tick...
               while(RefreshRates() == false)    // To the new tick
                  Sleep(1);                      // Cycle sleep
               continue;                         // At the next iteration
            case 146:                            // Trading subsystem is busy. Retrying...
               Sleep(500);                       // Try again
               RefreshRates();                   // Update data
               continue;                         // At the next iteration
            default:
               Alert(StringFormat("CloseMarketOrder error: %d", error));
               return(StringFormat("%d|%d", RESPONSE_FAILED, error));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all market orders.                                         |
//| Input:   SYMBOL                                                  |
//| Example: USDJPY                                                  |
//| Output:  CLOSED_COUNT                                            |
//| Example: 3                                                       |
//+------------------------------------------------------------------+
string CloseAllMarketOrders(
   string symbol
) {
   int closedCount = 0;
   
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      bool found = OrderSelect(i, SELECT_BY_POS);
      
      // Order not found or Symbol is not ours.
      if (!found || OrderSymbol() != symbol) continue;
      
      // Select only market orders.
      if (OrderType() < 2)
      {
         string response = CloseMarketOrder(OrderTicket());
         
         if (StringFind(response, (string)RESPONSE_OK) == 0)
         {
            closedCount++;
         }
      }
   }
   
   return(StringFormat("%d|%d", RESPONSE_OK, closedCount));
}

//+------------------------------------------------------------------+
//| Get rates for given symbol.                                      |
//| Input:   SYMBOL                                                  |
//| Example: USDJPY                                                  |
//| Output:  BID|ASK|SYMBOL                                          |
//| Example: 108.926000|108.947000|USDJPY                            |
//+------------------------------------------------------------------+
string GetRatesString(
   string symbol
) {
   double bid = MarketInfo(symbol, MODE_BID);
   double ask = MarketInfo(symbol, MODE_ASK);
   
   return(StringFormat("%d|%f|%f|%s", RESPONSE_OK, bid, ask, symbol));
}

//+------------------------------------------------------------------+
//| Get account info.                                                |
//| Input:   <empty>                                                 |
//| Output:  CURRENCY|BALANCE|PROFIT|EQUITY_MARGIN|MARGIN_FREE|      |
//|             MARGIN_LEVEL|MARGIN_SO_CALL|MARGIN_SO_SO             |
//| Example: USD|10227.43|-129.46|10097.97|4000.00|6097.97|252.45|   |
//|             50.00|20.00                                          |
//+------------------------------------------------------------------+
string GetAccountInfoString()
{
   return(
      (string)RESPONSE_OK + "|" + AccountInfoString(ACCOUNT_CURRENCY) + "|" +
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "|" +
      DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + "|" +
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "|" +
      DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN), 2) + "|" +
      DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + "|" +
      DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2) + "|" +
      DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL), 2) + "|" +
      DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_SO_SO), 2)
   );
}

//+------------------------------------------------------------------+
//| Get account orders.                                              |
//| Input:   <empty>                                                 |
//| Output:  TICKET,OPEN_TIME,TYPE,LOTS,SYMBOL,OPEN_PRICE|...        |
//| Example: 140617577,2018.05.31 10:40,1,0.01,EURUSD,1.17017,|      |
//|             140623054,2018.05.31 14:20,3,0.11,USDJPY,130.72600,  |
//+------------------------------------------------------------------+
string GetAccountOrdersString()
{
   string accountStr = "";
   int ordersCount = OrdersTotal();
   
   for (int i = 0; i < ordersCount; i++)
   {
      if (OrderSelect(i, SELECT_BY_POS) == false) continue;
      
      accountStr += IntegerToString(OrderTicket()) + "," +
         TimeToString(OrderOpenTime()) + "," +
         IntegerToString(OrderType()) + "," +
         DoubleToString(OrderLots(), 2) + "," +
         OrderSymbol() + "," +
         DoubleToString(OrderOpenPrice(), 5) + "," +
         //DoubleToString(OrderStopLoss(), 5) + "," +
         //DoubleToString(OrderTakeProfit(), 5) + "," +
         //DoubleToString(OrderCommission(), 2) + "," + 
         //DoubleToString(OrderSwap(), 2) + "," +
         //DoubleToString(OrderProfit(), 2) + "," +
         //"<" + OrderComment() + ">"
         "|";
   }
   
   if (accountStr != "")
   {
      accountStr = StringSubstr(accountStr, 0, StringLen(accountStr) - 1);
   }
   
   return(StringFormat("%d|%s", RESPONSE_OK, accountStr));
}

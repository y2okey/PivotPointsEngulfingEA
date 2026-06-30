//+------------------------------------------------------------------+
//|                                        PivotPointsEngulfingEA.mq5 |
//|                        Copyright 2026, Grok Assistant             |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Grok Assistant"
#property link      ""
#property version   "1.00"
#property strict
#property description "EA based on Daily Classic Pivot Points + Engulfing on M15"

#include <Trade\Trade.mqh>

//--- Inputs
input int    MagicNumber          = 123456;      // Magic Number
input double StartLot             = 0.01;        // Начальный лот
input double MartingaleMultiplier = 2.0;         // Множитель Мартингейла
input int    MaxMartingaleSteps   = 3;           // Макс. шагов мартингейла
input double MaxLot               = 1.0;         // Максимальный лот
input int    SL_BufferPoints      = 15;          // Буфер SL в пунктах
input int    TouchBufferPoints    = 10;          // Буфер касания уровней
input bool   UseEMAFilter         = true;        // Использовать EMA200 фильтр
input int    EMA_Period           = 200;         // Период EMA
input int    MaxSpreadPoints      = 30;          // Макс. спред в пунктах
input double MaxDrawdownPercent   = 20.0;        // Макс. просадка (%)
input int    StartHour            = 7;           // Начало торгового окна
input int    EndHour              = 22;          // Конец торгового окна

//--- Global variables
CTrade trade;
double dailyPP, dailyR1, dailyS1;
double prevDailyHigh, prevDailyLow, prevDailyClose;
datetime lastPivotTime = 0;
int currentMartingaleStep = 0;
double currentLot = 0.01;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   currentLot = StartLot;
   Print("EA PivotPointsEngulfing initialized");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsTradingTime()) return;
   if(GetSpread() > MaxSpreadPoints * _Point) return;
   if(IsMaxDrawdownReached()) return;

   // Update daily pivots once per day
   UpdateDailyPivots();

   if(PositionsTotal() > 0) 
     {
      ManageTrailingStop();
      return; // Only one position
     }

   CheckForSignals();
  }

//+------------------------------------------------------------------+
//| Update Classic Daily Pivot Points                                |
//+------------------------------------------------------------------+
void UpdateDailyPivots()
  {
   datetime currentDay = TimeCurrent() - (TimeCurrent() % 86400);
   if(currentDay == lastPivotTime) return;

   int dailyShift = iBarShift(_Symbol, PERIOD_D1, currentDay - 86400); // Previous day

   prevDailyHigh  = iHigh(_Symbol, PERIOD_D1, dailyShift);
   prevDailyLow   = iLow(_Symbol, PERIOD_D1, dailyShift);
   prevDailyClose = iClose(_Symbol, PERIOD_D1, dailyShift);

   dailyPP = (prevDailyHigh + prevDailyLow + prevDailyClose) / 3.0;
   dailyR1 = 2 * dailyPP - prevDailyLow;
   dailyS1 = 2 * dailyPP - prevDailyHigh;

   lastPivotTime = currentDay;
   Print("Daily Pivots updated: PP=", dailyPP, " R1=", dailyR1, " S1=", dailyS1);
  }

//+------------------------------------------------------------------+
//| Check for Buy/Sell signals                                       |
//+------------------------------------------------------------------+
void CheckForSignals()
  {
   if(!IsNewBar(PERIOD_M15)) return;

   double ema200 = iMA(_Symbol, PERIOD_M15, EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 1);

   // Bullish Engulfing detection
   bool bullishEngulfing = (Close[2] < Open[2]) && (Close[1] > Open[1]) && 
                           (Close[1] > Open[2]) && (Open[1] < Close[2]);

   // Bearish Engulfing
   bool bearishEngulfing = (Close[2] > Open[2]) && (Close[1] < Open[1]) && 
                           (Close[1] < Open[2]) && (Open[1] > Close[2]);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // BUY Signal
   if(ask <= dailyS1 + TouchBufferPoints * _Point)
     {
      if(bullishEngulfing)
        {
         if(!UseEMAFilter || bid > ema200)
           {
            OpenBuy();
            return;
           }
        }
     }

   // SELL Signal
   if(bid >= dailyR1 - TouchBufferPoints * _Point)
     {
      if(bearishEngulfing)
        {
         if(!UseEMAFilter || ask < ema200)
           {
            OpenSell();
            return;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Open Buy position                                                |
//+------------------------------------------------------------------+
void OpenBuy()
  {
   double sl = dailyS1 - SL_BufferPoints * _Point;
   double tp = dailyPP;

   if(trade.Buy(currentLot, _Symbol, 0, sl, tp, "Pivot Buy"))
     {
      Print("Buy opened. Lot: ", currentLot);
     }
  }

//+------------------------------------------------------------------+
//| Open Sell position                                               |
//+------------------------------------------------------------------+
void OpenSell()
  {
   double sl = dailyR1 + SL_BufferPoints * _Point;
   double tp = dailyPP;

   if(trade.Sell(currentLot, _Symbol, 0, sl, tp, "Pivot Sell"))
     {
      Print("Sell opened. Lot: ", currentLot);
     }
  }

//+------------------------------------------------------------------+
//| Trailing Stop (simple)                                           |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   // TODO: Implement proper trailing after profit distance
   // For now, basic check
  }

//+------------------------------------------------------------------+
//| Martingale logic after deal close                                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& req, const MqlTradeResult& res)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      if(res.retcode == TRADE_RETCODE_DONE)
        {
         // Check profit
         if(res.profit > 0)
           {
            currentLot = StartLot;
            currentMartingaleStep = 0;
           }
         else if(res.profit < 0)
           {
            currentMartingaleStep++;
            if(currentMartingaleStep <= MaxMartingaleSteps)
              {
               currentLot = NormalizeDouble(currentLot * MartingaleMultiplier, 2);
               if(currentLot > MaxLot) currentLot = MaxLot;
              }
            else
              {
               currentLot = StartLot;
               currentMartingaleStep = 0;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper functions                                                 |
//+------------------------------------------------------------------+
bool IsNewBar(int timeframe)
  {
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, timeframe, 0);
   if(currentTime != lastTime)
     {
      lastTime = currentTime;
      return true;
     }
   return false;
  }

bool IsTradingTime()
  {
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   return (tm.hour >= StartHour && tm.hour < EndHour);
  }

int GetSpread()
  {
   return (int)(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
  }

bool IsMaxDrawdownReached()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = (balance - equity) / balance * 100.0;
   return dd >= MaxDrawdownPercent;
  }

// Note: PositionsTotal() is built-in in newer MQL5, but to be safe:
int CountPositions()
  {
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
     }
   return count;
  }
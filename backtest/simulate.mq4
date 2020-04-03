//+------------------------------------------------------------------+
//|                                                     simulate.mq4 |
//|                        Copyright 2020, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2020, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
#define BUY  1
#define SELL 2

class HistData {
   #define INIT_SIZE 400000
   
   struct Candle {
      datetime Time;
      double Open, High, Low, Close;
   };
   
public:
   double pipsize;
   int data_cnt;
   string logname;

   Candle candle[];

   datetime myStrToTime(string date, string time) {
      return StrToTime(date + " " + time);
   }

   void logmsg(string str) {
      Print("log started");
      Print("log file name: " + logname);
      int logfile = FileOpen(logname, FILE_TXT|FILE_WRITE|FILE_READ, ",");
      if(FileSeek(logfile, 0, SEEK_END)) {
         FileWriteString(logfile, str + "\n");  
      }
      FileClose(logfile);
      Print("log finished");
   }
   
   HistData(string filename, double ps) {
      pipsize = ps;
      string xDate, splt[];
      logname = "backtest/logfile.txt";
      
      int logfile = FileOpen(logname, FILE_TXT|FILE_WRITE, ",");
      FileClose(logfile);

      int data = FileOpen(filename, FILE_TXT|FILE_READ, ",");
      int lines_cnt = 1;
      data_cnt = 0;
      ArrayResize(candle, INIT_SIZE);

      while (!FileIsEnding(data)) { 
         xDate = FileReadString(data);
         StringSplit(xDate, ',',splt);
         if (ArraySize(splt) >= 6) {
            candle[data_cnt].Time  =  myStrToTime(splt[0],splt[1]);
            candle[data_cnt].Open  =  StrToDouble(splt[2]);
            candle[data_cnt].High  =  StrToDouble(splt[3]);
            candle[data_cnt].Low   =  StrToDouble(splt[4]);
            candle[data_cnt].Close =  StrToDouble(splt[5]);
            data_cnt++;
         } else {
            // write log to file about corrupt data
            logmsg("Line " + IntegerToString(lines_cnt) + " has too little elements");
         }
                  
         lines_cnt++;
         if (lines_cnt == ArraySize(candle)) {
            ArrayResize(candle, ArraySize(candle) + INIT_SIZE);
         }
      }
      FileClose(data);
      
   }
   
   double Open(int i) {
      if (i >= data_cnt) {
         Print("HistData::Open: Out of range index " + IntegerToString(i));
         return -1;
      } else {
         return candle[i].Open;
      }
   }

   double High(int i) {
      if (i >= data_cnt) {
         Print("HistData::High: Out of range index " + IntegerToString(i));
         return -1;
      } else {
         return candle[i].High;
      }
   }
   
   double Low(int i) {
      if (i >= data_cnt) {
         Print("HistData::Low: Out of range index " + IntegerToString(i));
         return -1;
      } else {
         return candle[i].Low;
      }
   }
   
   double Close(int i) {
      if (i >= data_cnt) {
         Print("HistData::Close: Out of range index " + IntegerToString(i));
         return -1;
      } else {
         return candle[i].Close;
      }
   }
   
   int find_bar(datetime dt) {
      int cnt = 0;
      while (dt > candle[cnt].Time && cnt < data_cnt) {
         cnt++;
      }
      if (data_cnt == cnt) {
         logmsg("your operation time " + TimeToStr(dt) + " is too late for history data, it is available till " + TimeToStr(candle[data_cnt-1].Time));
         return -1; //candle not found
      } else {
         if (cnt == 0 && dt != candle[0].Time) {
            //count the differnce between desired time and first candle time
            logmsg("your operation time " + TimeToStr(dt) + " is too early for history data, it is available since " + TimeToStr(candle[0].Time));
            return -1;
         }
         return cnt; //first candle since dt time
      }
   }
   
   void get_report(datetime dt) {
      int pos = find_bar(dt);
      if (pos != -1) {
         Print("Bar #" + IntegerToString(pos) + " at time " + TimeToStr(dt) +
             ". Open: " + DoubleToStr(Open(pos)) + "; " + "High: " + DoubleToStr(High(pos)) +
              "; " + "Low: " + DoubleToStr(Low(pos)) + "; " + "Close: " + DoubleToStr(Close(pos)) + ".");
      }
   }
   
   int backtest(datetime dt, int optype, int sl, int tp) {
      /*
         We start trade at open price at a given time. Stop loss has greater priority than tp so 
         in case candle has both we choose worst scenario. 
      */
      int p = find_bar(dt);
      double price = Open(p);
      
      if (optype == BUY) {
         double slp = price - pipsize*sl;
         double tpp = price + pipsize*tp;
         while (p < data_cnt) {
            if (Low(p) <= slp) {
               //stop loss case
               return -sl;
            } else if (High(p) >= tpp) {
               //take profit case
               return tp;
            }
            p++;
         }
      } else if (optype == SELL) {
         double slp = price + pipsize*sl;
         double tpp = price - pipsize*tp;
         while (p < data_cnt) {
            if (High(p) >= slp) {
               //stop loss case
               return -sl;
            } else if (Low(p) <= tpp) {
               return tp;
            }
            p++;
         }
      }
      return -1;   
   }
};

class BacktestScenario {
   #define POSLISTMAXSIZE 1000
   struct Position {
      datetime timestart;
      int postype;
      int sl;
      int tp1;
      int tp2;
      int tp3; 
   };
   int poscnt;
   public:
   Position poslist[POSLISTMAXSIZE];
   BacktestScenario(string filename) {
      int handle = FileOpen(filename, FILE_TXT|FILE_READ, ",");
      Print("BacktestScenario constructor starts");
      Print("Attempt to read " + filename);
      if(handle > 0){
         Print("BacktestScenario constructor file found");
         string xDate, ymdhm, splt[], mdy[];
         xDate = FileReadString(handle); // read header file
         poscnt = 0;
         while (!FileIsEnding(handle)) {
            xDate = FileReadString(handle);
            Print("while loop");
            StringSplit(xDate, ',', splt);
            StringSplit(splt[0], '/', mdy);
            ymdhm = mdy[2] + "." + mdy[0] + "." + mdy[1] + " " + splt[1];
            datetime dt = StrToTime(ymdhm);
            poslist[poscnt].timestart = dt;
            // Print(splt[2]);
            if (StringFind(splt[2], "BUY", 0) >= 0) {
               // Print("BUY");
               poslist[poscnt].postype = BUY;
            } else {
               // Print("SELL");
               poslist[poscnt].postype = SELL;   
            }
            Print("splt[3] = " + splt[3]);
            poslist[poscnt].sl = StrToInteger(splt[3]);
            poslist[poscnt].tp1 = StrToInteger(splt[4]);
            poslist[poscnt].tp2 = StrToInteger(splt[5]);
            poslist[poscnt].tp3 = StrToInteger(splt[6]);
            poscnt++;
            if (poscnt == POSLISTMAXSIZE) {
               break; //too much positions in the list;
            }
         }
      }
      FileClose(handle);
   }
   
   string optype(int opt) {
      if (opt == BUY) {
         return "BUY";
      } else if (opt == SELL) { 
         return "SELL";
      }
      return "SHIT";   
   }
   
   void printpos(int cnt) {
      Print("printpos, poscnt = " + IntegerToString(poscnt));
      if (cnt>=0 && cnt < poscnt) {
         Print(TimeToStr(poslist[cnt].timestart) + ": " + optype(poslist[cnt].postype) + " sl=" + 
         IntegerToString(poslist[cnt].sl) + " tp1=" + IntegerToString(poslist[cnt].tp1) + " tp2=" + 
         IntegerToString(poslist[cnt].tp2) + " tp3=" + IntegerToString(poslist[cnt].tp3));
      }
   }
   
   string pos_to_string(int cnt) {
      return (TimeToStr(poslist[cnt].timestart) + ", " + optype(poslist[cnt].postype) + ", " + IntegerToString(poslist[cnt].sl) 
      + ", " + IntegerToString(poslist[cnt].tp1) + ", " + IntegerToString(poslist[cnt].tp2) + ", " + IntegerToString(poslist[cnt].tp3)) + "\n";
   }
   
   void run(HistData &hist, string resfile) {
      int res = FileOpen(resfile, FILE_TXT|FILE_WRITE, ",");
      if (res > 0) {
         FileWriteString(res, "Time, Operation, SL, TP1, TP2, TP3 \n");
         for (int i=0; i<poscnt; i++) {
            FileWriteString(res, pos_to_string(i));
//            hist.find_bar()
//            FileWriteString(res, ); // line of actual prices
            int tp1_profit = hist.backtest(poslist[i].timestart, poslist[i].postype, poslist[i].sl, poslist[i].tp1);
            int tp2_profit = hist.backtest(poslist[i].timestart, poslist[i].postype, poslist[i].sl, poslist[i].tp2);
            int tp3_profit = hist.backtest(poslist[i].timestart, poslist[i].postype, poslist[i].sl, poslist[i].tp3);
            FileWriteString(res, ",,," + IntegerToString(tp1_profit) + "," + IntegerToString(tp2_profit) + "," + IntegerToString(tp3_profit)+ "\n");
         }
      } else {
         Print("file " + resfile + " not open");
      }
      FileClose(res);
   }
};

void OnStart() {
//---
   /*
      int handle=0;
      Print("script simulate started");
      handle = FileOpen("sample.csv", FILE_TXT|FILE_READ,",");
      if(handle > 0){
         Print("handle > 0");
         string xDate, ymdhm, splt[], mdy[];
         xDate = FileReadString(handle);
         Print(xDate);
         
         while (!FileIsEnding(handle)) {
            xDate = FileReadString(handle);
            Print(xDate);
            StringSplit(xDate, ',',splt);
            //---            Print(result[0] + "; total length is " + IntegerToString(ArraySize(result)));
            StringSplit(splt[0], '/', mdy);
            Print("splt[0] = " + splt[0] + ", mdy size " + IntegerToString(ArraySize(mdy)));
            ymdhm = mdy[2] + "." + mdy[0] + "." + mdy[1] + " " + splt[1];
            Print(ymdhm);
            datetime dt = StrToTime(ymdhm);
//---            datetime some_time = D'2004.03.21 12:00';
            int period = PERIOD_M1;
            Print(dt);
            int shift = iBarShift("EURUSD",period,dt);
            //---            datetime dt2 = D'2020.03.19 12:00';
            // int shift2 = iBarShift(Symbol(),period,dt2,True);

            Print("shift = " + IntegerToString(shift));
            // Print("shift2 = " + IntegerToString(shift2));
            Print("Open price at " + ymdhm + " was " + DoubleToString(iOpen(NULL, period, shift)));
         }
         
      FileClose(handle);
      
      Print("simulated finished correctly");
      Print("iBars = " + IntegerToString(iBars("EURUSD",PERIOD_M1)));
      // currently get time and see the open price there
   }
   *
   uint s1 = GetTickCount(); 
   int handle = FileOpen("EURUSD_M1_2019.csv", FILE_TXT|FILE_READ,",");
   string xDate;
   int lines_cnt = 0;
   while (!FileIsEnding(handle)) { 
      xDate = FileReadString(handle);
      lines_cnt++;
   }
   uint s2 = GetTickCount() - s1; 
   

   Print("lines_cnt = " + IntegerToString(lines_cnt));
   Print("Time elapsed: " + DoubleToString((double)s2/1000) + "s");
   */

   HistData data("backtest/EURUSD_M1_2019.csv", 0.0001);
   Print("data.Open(0) = " + DoubleToStr(data.Open(0)));
   Print("data.High(0) = " + DoubleToStr(data.High(0)));
   Print("data.Low(0) = " + DoubleToStr(data.Low(0)));
   Print("data.Close(0) = " + DoubleToStr(data.Close(0)));


   Print("data.Open(10) = " + DoubleToStr(data.Open(10)));
   Print("data.High(10) = " + DoubleToStr(data.High(10)));
   Print("candle array size = " + IntegerToString(ArraySize(data.candle)));
   Print("number of actual records in candle array = " + IntegerToString(data.data_cnt));
   Print("end of script");
   
   Print("First candle position is " + IntegerToString(data.find_bar(D'2019.12.31 12:51')));
   data.get_report(D'2019.05.31 7:33');
   data.get_report(D'2019.05.31 7:34');
   BacktestScenario backtest("backtest/conditions.csv");
   backtest.printpos(0);
   backtest.printpos(8);
   
   backtest.run(data,"backtest/result.csv");
}

//+------------------------------------------------------------------+

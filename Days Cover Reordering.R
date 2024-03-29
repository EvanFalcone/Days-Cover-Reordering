## DEMAND FORECASTING FOR REORDERING
## Evan Falcone
## August 17th, 2016

## One of the biggest questions we face is "How much product should we order (pre SKU) so that we're not using up money in warehouse space, but also have enough stock
## for when orders come in." So far, we are just eyeballing it based on the availability of product and projected future availability. We would like to quantify that
## as much as possible to take out the guessing for our buyer.

## The forecasting methods to try include: stlf(), HoltWinters(), Arima() (auto.arima())

## I) ORDER HISTORY: Given order history we can see how much we've ordered in the past, condition on that and get numbers for how much to order in the future. Problem
## is, we don't actually know if what we've been ordering in the past was good or not! Not to mention not all orders get filled/invoiced, so many end up getting scrapped.
## All in all - NOT reliable!

## II) SALES HISTORY: Based on how much product is selling, we tailor our orders accordingly (something that moves faster will require more stock, less for
## slow-moving). How do we get sales data (x - variable) to reflect orders (y - variable)? Doesn't work exactly like regression...


## |-----------------------------------------------------------------------------------------------------------------------------------------------------------------|


## Need to first install the packages (below), then load the packages using library() (next/below)
# install.packages("plyr")
# install.packages("zoo")
# install.packages("forecast")
# install.packages("tsintermittent")
# install.packages("xts")

library("plyr")
library("zoo")
library("forecast")
library("tsintermittent")
library("xts")
library("openxlsx")


## What James C needs from my R script is the "target stock amount, which I can feed into the PMS and it'll adjust for current stock and POs on back order to arrive
## at the figure to order on the next PO run."

# Set working directory and CHANGE CUTOFF DATE of the data (in theory, current date/date the code is being run):
setwd("/Users/evan/Documents/FORECASTING DEMAND PROJECT/")
todayDate <- sys.Date()

## CUSTOM FUNCTIONS:

# Truncates to first day of the month:
firstDayMonth = function(x) {
  
     x=as.Date(as.character(x))
     day = format(x,format="%d")
     monthYr = format(x,format="%Y-%m")
     y = tapply(day,monthYr, min)
     first=as.Date(paste(row.names(y),y,sep="-"))
     as.factor(first)
     
}

# Convert dataframe to zoo format:
dfTozoo = function(tsdataframe, dateformat="%m/%d/%Y") {

  library(zoo)

  framedates = as.Date(tsdataframe[,1], format=dateformat)
  n=ncol(tsdataframe)
  zoodata = zoo(tsdataframe[,2:n], order.by=framedates)

  return(zoodata)
  
}


## SQL CODE:

# USE Isotope_Music_Inc_Live;
# GO
# 
# SELECT *
# FROM Invoices i
# INNER JOIN InvoiceLines il
# ON i.InvoiceId = il.InvoiceId
# WHERE i.InvoiceType != 'Credit'
# AND InvoiceDate >= "2016-06-17"
# ORDER BY InvoiceDate ASC

# Links to data files:
TestSalesAll <- "Reordering Sony between Dates.txt"
## Read in Sales Data:
TestSalesData <- read.delim(TestSalesAll, sep="|", quote=NULL, comment='', header=TRUE, stringsAsFactors = FALSE)
# You can keep this check in in case there are NAs, but the NAs you currently see are due to the presence of "|" in "Description" column!
# TestSalesData <- subset(TestSalesData, !is.na(TestSalesData$Quantity))

## Get rid of useless cols, make sure col classes are correct and get rid of NA quantities (those rows need fixing - have "|" in them - choose obscure custom delim?):
TestSalesTrimMore <- TestSalesData[,c(3,27,29)]
TestSalesTrimMore$InvoiceDate <- as.Date(as.character(TestSalesTrimMore$InvoiceDate))
TestSalesTrimMore$InvoiceDate <- as.character(TestSalesTrimMore$InvoiceDate)
TestSalesTrimMore$Quantity <- as.numeric(TestSalesTrimMore$Quantity)
TestSalesTrimMore <- subset(TestSalesTrimMore, !is.na(TestSalesTrimMore$Quantity))

## Group the data by ProductId:
listTestSalesTrim <- split(TestSalesTrimMore, f = TestSalesTrimMore$ProductId)
listTestSalesTrim <- lapply(listTestSalesTrim, function(x) x[,c(1,3), drop=FALSE])

## Sum any duplicate quantities together (with equal dates), rename the list elements by ProductId and return 'InvoiceDate' to Date class:
AggregSalesTrim <- lapply(seq_along(along.with = listTestSalesTrim), function(x) aggregate(Quantity ~ InvoiceDate, data = listTestSalesTrim[[x]], FUN = sum))
names(AggregSalesTrim) <- names(listTestSalesTrim)
AggregSalesTrim <- lapply(AggregSalesTrim, function(x) { cbind(InvoiceDate = as.Date(as.character(x$InvoiceDate)), data.frame(Quantity = x$Quantity, stringsAsFactors = FALSE)) })


## *****************************************************************


## 30 DAY AVERAGE METHOD (like James C suggested - fallback when insufficient data for forecasting):

# Sequence of last thirty days in 'Date' format up to 'todayDate':
seq_dates_list <- lapply(testShitOut, function(z) { seq.Date(from = todayDate - 60, to = todayDate, by = "day") })

all_dates_df <- lapply(seq_dates_list, function(z) { data.frame(list(InvoiceDate = z)) })

merge_ts <- mapply(function(x, y) merge(x, y, by = "InvoiceDate", all.x = T), x = all_dates_df, y = testShitOut, SIMPLIFY = F)
merge_all <- lapply(merge_ts, function(z) { data.frame(InvoiceDate = as.Date(as.character(z$InvoiceDate)), Quantity = ifelse(is.na(z$Quantity), 0, z$Quantity),
                                                       stringsAsFactors = FALSE) })
monthMean <- lapply(merge_all, function(z) { round(mean(z$Quantity)) })

# zoo_obj <- zoo(c(NA,NA,rnorm(118,100,2),NA,NA), seq_dates)
# listZoo <- lapply(merge_all, dfTozoo)
# listZooTs <- lapply(listZoo, function(z) { as.ts(z) })

# listTestForecastTs <- lapply(listZooTs, auto.arima, seasonal = FALSE)
# listTestForecastZoo <- lapply(listZoo, auto.arima, seasonal = FALSE)
# Here, we get an error because there are missing data points (i.e. stl() can't deal with xts/zoo, only ts class).


## *****************************************************************


## ASSUMPTION VALUES:
## Concept of Cutoff date is related to the LEAD TIME - lead time is determined by the speed of the supply chain. For now, I'm assuming that
## the lead time will be provided (by James C, I imagine), so we'll assume some fixed will; for now, 3 days.
# (recall that, internally, R Dates are stored as the number of days since Jan 1st, 1970 - so, as.numeric(Jan 4th, 1970))

LeadTimeNum <- as.numeric(as.Date('1970-01-8'))
ServiceLevel <- 0.9


## SPREADSHEET COMPUTATION:
LeadTimeDemand <- monthMean #sum of point forecast values

STD <- lapply(merge_all, function(z) { mad(z$Quantity) }) #std in past sales data, use either sd or mad
ServiceFact <- qnorm(ServiceLevel)
LeadTimeFact <- sqrt(LeadTimeNum)
SafetyStock <- lapply(STD, function(z) { z * ServiceFact * LeadTimeFact })

ReorderPoint <- mapply("+", LeadTimeDemand, SafetyStock, SIMPLIFY = F)
ReorderPointRound <- lapply(ReorderPoint, round)
ReorderPointDF <- data.frame(ReorderPoint = unlist(ReorderPointRound), stringsAsFactors = FALSE)

# d <- ReorderPointDF
#   names <- rownames(d)
#   rownames(d) <- NULL
#   data <- cbind(names,d)
# names(data) <- c("ProductID","ReorderPoint")

IsoData <- "/Users/evan/Documents/FORECASTING DEMAND PROJECT/SONY SUPP Barcodes Reordering Algorithm.txt"
InventoryDF <- read.delim(IsoData, sep = "|", stringsAsFactors = FALSE, fill = TRUE, quote = "", colClasses = "character")

IsoMerge <- merge(InventoryDF, data, by = "ProductID", all = FALSE)

# Save to .xlsx:
# openxlsx::write.xlsx(IsoMerge, file = "ReorderPoint.xlsx")


## |-----------------------------------------------------------------------------------------------------------------------------------------------------------------|

library(tabulizer)
library(miniUI)
library(tidyverse)
library(purrr)
library(slider)
library(gt)

#Some important Variables to define the overall list of sessions to process
session <- c("FP1")#,"FP2","FP3","FP4","Q1","Q2","WUP")
event   <- c("SPA")#,"ARG","AME","SPA","FRA","ITA","CAT","NED","GER","AUT","CZE","GBR","RSM")
j <- rep(sprintf(session), each = length(event)) 
i <- sprintf(event)
urls <- paste0("http://resources.motogp.com/files/results/2021/", i, "/MotoGP/", j,"/Analysis.pdf")
entry_url <- paste0("https://resources.motogp.com/files/results/2021/", i, "/MotoGP/Entry.pdf")
ses <- paste(i, j, sep = "-")

AA <- c(164.88604, 53.921875, 731.85, 314.978125)
AB <- c(164.88604, 317.953125, 731.85, 576.7781250)
ZA <- c(40.90625, 53.921875, 731.85, 314.978125)
ZB <- c(40.90625, 317.9531255, 731.85, 576.778125)

entry_area <- c(134.12389, 60.92034, 444.59587, 550.22420)

# Regexps:
rexp_times = "(\\d+\\'\\d{2}\\.\\d{3}|\\d{2,3}\\.\\d{3})"
rexp_pos = "\\d+(st|nd|rd|th)"
rexp_total_laps = "(?<=Total laps\\=)\\d+"
rexp_full_laps = "(?<=Full laps\\=)\\d+"
rexp_runs = "(?<=Runs\\=)\\d+"
rexp_f_tire = "(?<=(F|f)ront\s+Tyre\s+)(((S|s)lick|(W|w)et)-(Hard|Medium|Soft))"
rexp_r_tire = "(?<=(R|r)ear\s+Tyre\s+)(((S|s)lick|(W|w)et)-(Hard|Medium|Soft))"
rexp_tire_life = "(\\d+(?= Laps at start)|New Tyre)"
rexp_speed = "\\d{2,3}\\.\\d{1}(?!\\d)"
rexp_rider_number = "(?<=(1st|2nd|3rd|4th|5th|6th|7th|8th|9th|0th)\\s)\\d+"
rexp_run_number = "(?<=Run\\s?#\\s?)\\d+"
rexp_lap_number = "\\d+(?=\\s)"
#Get The Area Function
GetArea <- function(x) {
  y <- vector('list',x)
  for (i in seq(x)) {
    if (i == 1) { y[[i]] <- AA}
    else if (i == 2) { y[[i]] <- AB}
    else if (i %% 2 != 0) {y[[i]] <- ZA}
    else {y[[i]] <- ZB}
  }
  return(y)
}



for ( i in seq(urls)) {
  p <- get_n_pages(urls[i])
  pages <- as.numeric(as.integer(seq(1, p + .5, .5)))
  area <- GetArea(2*p)
  
  ts <- extract_tables(urls[i], pages = pages, guess = FALSE, area = area)
  
  for (i in seq(length(ts)) ) {
    ts[[i]] <- ts[[i]][,which(!apply(ts[[i]],2,FUN = function(x){all(x == "")}))] %>% 
      as_tibble() %>% 
      unite("data", sep=" ")
  }
  
  results <- ts %>% 
    reduce(rbind)
    
}

riders <- extract_tables(entry_url, pages=1, guess=FALSE, area = list(entry_area), output = "data.frame")[[1]] %>%  as_tibble()

results %>%
  mutate(LapTime     = str_extract(data, rexp_times),
         TotalLaps   = as.integer(str_extract(data, rexp_total_laps)),
         FullLaps    = as.integer(str_extract(data, rexp_full_laps)),
         speed       = as.double(str_extract(data, rexp_speed)),
         FrontTire   = str_extract(data, rexp_f_tire),
         RearTire    = str_extract(data, rexp_r_tire),
         run_number  = as.integer(str_extract(data, rexp_run_number)),
         riderNumber = as.integer(str_extract(data, rexp_rider_number)),
         pitting     = str_extract(data, 'P'),
         invalidatedLap = str_extract(data, "\\*")) %>%
  left_join(riders, c("riderNumber" = "X.1")) %>% 
  fill(c("riderNumber","X","Rider","Nation","Team","Motorcycle","run_number","FrontTire","RearTire","TotalLaps","FullLaps")) %>%
  slice(-1) %>%
  group_by(Rider, data) %>% 
  mutate(
    T1 = as.double(str_extract_all(data, rexp_times)[[1]][2]),
    T2 = as.double(str_extract_all(data, rexp_times)[[1]][3]),
    T3 = as.double(str_extract_all(data, rexp_times)[[1]][4]),
    T4 = as.double(str_extract_all(data, rexp_times)[[1]][5])
  ) %>% 
  mutate(
    Front_tire_age = str_extract_all(data, rexp_tire_life)[[1]][1],
    Rear_tire_age  = str_extract_all(data, rexp_tire_life)[[1]][2],
    Front_tire_age = as.integer(recode(Front_tire_age, "New Tyre" = "0")),
    Rear_tire_age = as.integer(recode(Rear_tire_age, "New Tyre" = "0")),
    is_lap = !is.na(LapTime)
  ) %>%
  group_by(Rider, is_lap) %>% 
  mutate(
    LapNumber = case_when(is_lap ~row_number()),
    LapType =  case_when(
      !is.na(pitting) & is_lap ~ "In",
      !is.na(lag(pitting)) & is_lap  ~ "Out",
      LapNumber == 1 ~ "Out",
      TRUE ~ "Speed"
    ),
    run_number = case_when(is_lap ~ run_number)
  ) %>%
  select(data, is_lap, riderNumber, Rider:Motorcycle, X, TotalLaps, FullLaps, run_number, FrontTire, RearTire, Front_tire_age, Rear_tire_age, invalidatedLap, LapNumber, LapType, LapTime, T1, T2, T3, T4, speed) %>%
  group_by() %>% 
  fill(c("Front_tire_age", "Rear_tire_age")) %>%
  group_by(Rider, run_number, is_lap) %>%
  mutate(
    Front_tire_age = min(Front_tire_age, na.rm=TRUE) + row_number() -1,
    Rear_tire_age = min(Rear_tire_age, na.rm=TRUE) + row_number() -1
  ) %>%
  group_by()
  



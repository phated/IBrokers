ibgConnect <- function(clientId=1, host="localhost",
                                   port=4001, verbose=TRUE,
                                   timeout=5, filename=NULL,
                                   blocking=.Platform$OS.type=="windows") {
  twsConnect(clientId, host, port, verbose, timeout, filename)
}

twsConnect <- twsConnect2 <- function(clientId=1, host="localhost",
                                      port=7496, verbose=TRUE,
                                      timeout=5, filename=NULL,
                                      blocking=.Platform$OS.type=="windows") {
   startApi <- function(conn, clientId) {
     if (!is.twsConnection(conn)) {
       stop("requires twsConnection object")
     }
     con <- conn[[1]]
     VERSION <- "1"
     writeBin(.twsOutgoingMSG$START_API, con)
     writeBin(VERSION, con)
     writeBin(as.character(clientId), con)
   }

   if(is.null(getOption('digits.secs'))) 
     options(digits.secs=6)

   if(is.character(clientId))
     filename <- clientId

   if(is.null(filename)) {
     start.time <- Sys.time()
     s <- socketConnection(host = host, port = port,
                           open='ab', blocking=blocking)

     on.exit(close(s))
     if(!isOpen(s)) { 
       close(s)
       stop(paste("couldn't connect to TWS on port",port))
     }
     CLIENT_VERSION <- "63"

     writeBin(CLIENT_VERSION, s)

     eW <- eWrapper(NULL)
     eW$.Data <- environment()
     SERVER_VERSION <- NEXT_VALID_ID <- CONNECTION_TIME <- NULL
     eW$nextValidId <- function(curMsg, msg, timestamp, file, ...) {
       eW$.Data$NEXT_VALID_ID <- msg[2]
     }
     
     # server version and connection time
     while(TRUE) {
       if( !is.null(CONNECTION_TIME))
         break
       if( !socketSelect(list(s), FALSE, 0.1))
         next
       curMsg <- readBin(s, character(), 1)

       if(is.null(SERVER_VERSION)) {
         SERVER_VERSION <- curMsg[1]
         CONNECTION_TIME <- readBin(s, character(), 1)
         next
       }

       if(Sys.time()-start.time > timeout) {
         close(s)
         stop('tws connection timed-out')
       }
     }
     on.exit() # successful connection

     twsconn <- new.env()
     twsconn$conn <- s
     twsconn$clientId <- clientId
     twsconn$nextValidId <- NEXT_VALID_ID
     twsconn$port <- port
     twsconn$server.version <- SERVER_VERSION
     twsconn$connected.at <- CONNECTION_TIME
     twsconn$connected <- NULL # not yet used
     class(twsconn) <- c("twsconn","environment")

     # set the clientId (needs an API call now)
     startApi(twsconn, clientId)

     # server responds with:
     # 1) managed account message
     # 2) next valid id
     # 3) status messages about data farms (market and time)
     #    these are 'errors', but the id is -1
     while(TRUE) {
       if(socketSelect(list(s), FALSE, 0.1)) {
         curMsg <- readBin(s, character(), 1)
         if(curMsg == .twsIncomingMSG$MANAGED_ACCTS) {
           processMsg(curMsg, s, eW, NULL, "")
         } else
         if(curMsg == .twsIncomingMSG$NEXT_VALID_ID) {
           twsconn$nextValidId <- processMsg(curMsg, s, eW, NULL, "")
         } else
         if(curMsg == .twsIncomingMSG$ERR_MSG) {
           processMsg(curMsg, s, eW, NULL, "")
         }
       } else {
         break
       }
     }

     return(twsconn)
  } else { 
    #file is defined - not a real connection
    fh <- file(filename,open='r')
    dat <- scan(fh, what=character(), quiet=TRUE)
    close(fh)

    tmp <- tempfile()
    fh <- file(tmp, open='ab')

    writeBin(dat, fh)

    close(fh)
    s <- file(tmp, open='rb')

     twsconn <- new.env()
     twsconn$conn <- s
     twsconn$clientId <- NULL
     twsconn$nextValidId <- NULL
     twsconn$port <- NULL
     twsconn$server.version <- NULL
     twsconn$connected.at <- filename
     class(twsconn) <- c("twsplay","twsconn","environment")
     return(twsconn)
  }
}
                       
.twsConnect <-
function (clientId=1, host='localhost', port = 7496, verbose=TRUE,
          timeout=5, filename=NULL,
          blocking=TRUE)
 {
   if(is.null(getOption('digits.secs'))) 
     options(digits.secs=6)

   if(is.character(clientId))
     filename <- clientId

   if(is.null(filename)) {
     start.time <- Sys.time()
     s <- socketConnection(host = host, port = port,
                           open='ab', blocking=blocking)

     if(!isOpen(s)) { 
       close(s)
       stop(paste("couldn't connect to TWS on port",port))
     }

     CLIENT_VERSION <- "45"
     writeBin(c(CLIENT_VERSION,as.character(clientId)), s)
     Sys.sleep(1)
     
     while(TRUE) {
       curMsg <- readBin(s, character(), 1)
       if(length(curMsg) > 0) {
         if(curMsg == .twsIncomingMSG$ERR_MSG) {
           if(!errorHandler(s,verbose)) stop() 
         } else {
         SERVER_VERSION <- curMsg
         CONNECTION_TIME <- readBin(s,character(),1)
         NEXT_VALID_ID <- readBin(s,character(),3)[3]
         break
         }
       }
       if(Sys.time()-start.time > timeout) {
         close(s)
         stop('tws connection timed-out')
       }
     }
     on.exit() # successful connection

     structure(list(s,
                    clientId=clientId,port=port,
                    server.version=SERVER_VERSION,
                    connected.at=CONNECTION_TIME), 
                    class = "twsConnection")
  } else { 
    #file is defined - not a real connection
    fh <- file(filename,open='r')
    dat <- scan(fh, what=character(), quiet=TRUE)
    close(fh)

    tmp <- tempfile()
    fh <- file(tmp, open='ab')

    #writeBin(c(as.character(length(dat)),dat), fh)
    writeBin(dat, fh)
    #for(i in dat) writeBin(i, fh)

    close(fh)
    s <- file(tmp, open='rb')

    structure(list(s,
                   clientId=NULL,port=NULL,
                   server.version=NULL,
                   connected.at=filename), 
                   class = c("twsPlayback","twsConnection"))

  }
}

is.twsConnection <- function(x)
{
  inherits(x, "twsConnection") || inherits(x, "twsconn")
}

is.twsPlayback <- function(x)
{
  inherits(x, "twsPlayback") || inherits(x, "twsplay")
}

isConnected <- function(twsconn)
{
#  if( !.Call("still_alive", twsconn[[1]]))
#    return(FALSE)

  is_open <- function(con) {
    if(inherits(try(isOpen(con), silent=TRUE), 'try-error')) {
      FALSE
    } else TRUE 
  }
  if( !is.twsConnection(twsconn)) {
    warning("isConnected requires a twsconn object")
    return(FALSE)
  }

  if( !is.null(twsconn$connected)) {
    return( is_open(twsconn[[1]]) && twsconn$connected )
  } else {
    is_open(twsconn[[1]])
  }

#  if(is.twsConnection(x)) {
#    if(inherits(try(isOpen(x[[1]]), silent=TRUE), 'try-error')) {
#      FALSE
#    } else TRUE 
#  } else isOpen(x)
} 

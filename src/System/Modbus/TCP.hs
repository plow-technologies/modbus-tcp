{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE PackageImports     #-}
{-# LANGUAGE UnicodeSyntax      #-}

-- | An implementation of the Modbus TPC/IP protocol.
--
-- This implementation is based on the @MODBUS Application Protocol
-- Specification V1.1b@
-- (<http://www.modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf>).
module System.Modbus.TCP
  ( TCP_ADU(..)
  , Header(..)
  , FunctionCode(..)
  , ExceptionCode(..)
  , MB_Exception(..)

  , TransactionId
  , ProtocolId
  , UnitId

  , command

  , readCoils
  , readDiscreteInputs
  , readHoldingRegisters
  , readInputRegisters
  , writeSingleCoil
  , writeSingleRegister
  , writeMultipleRegisters
  ) where

import "base" Control.Applicative ( (<*>) )
import "base" Control.Exception.Base ( Exception )
import "base" Control.Monad ( replicateM, mzero )
import "base" Data.Functor ( (<$>) )
import "base" Data.Word ( Word8, Word16 )
import "base" Data.Typeable ( Typeable )
import "base-unicode-symbols" Data.Bool.Unicode     ( (∧), (∨) )
import "base-unicode-symbols" Data.List.Unicode     ( (∈) )
import "base-unicode-symbols" Data.Ord.Unicode      ( (≤), (≥) )
import "base-unicode-symbols" Data.Function.Unicode ( (∘) )
import "cereal" Data.Serialize
  ( Serialize, put, get, Get
  , encode, decode
  , runPut, runGet
  , putWord8, putWord16be
  , getWord8, getWord16be
  , getByteString
  )
import           "bytestring" Data.ByteString ( ByteString )
import qualified "bytestring" Data.ByteString as BS
import qualified "network" Network.Socket as S hiding ( send, recv )
import qualified "network" Network.Socket.ByteString as S ( send, recv )


type TransactionId = Word16
type ProtocolId    = Word16
type UnitId        = Word8

-- | MODBUS TCP/IP Application Data Unit
--
-- See: MODBUS Application Protocol Specification V1.1b, section 4.1
data TCP_ADU =
  TCP_ADU { aduHeader   ∷ Header
          , aduFunction ∷ FunctionCode
          , aduData     ∷ ByteString
          } deriving Show

instance Serialize TCP_ADU where
  put (TCP_ADU header fc ws) = put header >> put fc >> mapM_ putWord8 (BS.unpack ws)
  get = do
    header ← get
    fc     ← get
    ws     ← getByteString $ fromIntegral (hdrLength header) - 2
    return $ TCP_ADU header fc ws

-- | MODBUS Application Protocol Header
--
-- See: MODBUS Application Protocol Specification V1.1b, section 4.1
data Header =
  Header { hdrTransactionId ∷ TransactionId
         , hdrProtocolId    ∷ ProtocolId
         , hdrLength        ∷ Word16
         , hdrUnitId        ∷ UnitId
         } deriving Show

instance Serialize Header where
  put (Header tid pid len uid) =
    putWord16be tid >> putWord16be pid >> putWord16be len >> putWord8 uid
  get = Header <$> getWord16be <*> getWord16be <*> getWord16be <*> getWord8

-- | The function code field of a MODBUS data unit is coded in one
-- byte. Valid codes are in the range of 1 ... 255 decimal (the range
-- 128 - 255 is reserved and used for exception responses). When a
-- message is sent from a Client to a Server device the function code
-- field tells the server what kind of action to perform. Function
-- code 0 is not valid.
--
-- Sub-function codes are added to some function codes to define
-- multiple actions.
--
-- See: MODBUS Application Protocol Specification V1.1b, sections 4.1 and 5
data FunctionCode =
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.1
    ReadCoils
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.2
  | ReadDiscreteInputs
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.3
  | ReadHoldingRegisters
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.4
  | ReadInputRegisters
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.5
  | WriteSingleCoil
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.6
  | WriteSingleRegister
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.7
  | ReadExceptionStatus
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.8
  | Diagnostics
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.9
  | GetCommEventCounter
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.10
  | GetCommEventLog
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.11
  | WriteMultipleCoils
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.12
  | WriteMultipleRegisters
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.13
  | ReportSlaveID
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.14
  | ReadFileRecord
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.15
  | WriteFileRecord
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.16
  | MaskWriteRegister
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.17
  | ReadWriteMultipleRegisters
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.18
  | ReadFIFOQueue
    -- | See: MODBUS Application Protocol Specification V1.1b, section 6.19
  | EncapsulatedInterfaceTransport
    -- | See: MODBUS Application Protocol Specification V1.1b, section 5
  | UserDefinedCode   Word8
    -- | See: MODBUS Application Protocol Specification V1.1b, section 5
  | ReservedCode      Word8
  | OtherCode         Word8
  | ExceptionCode FunctionCode
    deriving Show

instance Serialize FunctionCode where
  put = putWord8 ∘ enc
    where
      enc ∷ FunctionCode → Word8
      enc ReadCoils                      = 0x01
      enc ReadDiscreteInputs             = 0x02
      enc ReadHoldingRegisters           = 0x03
      enc ReadInputRegisters             = 0x04
      enc WriteSingleCoil                = 0x05
      enc WriteSingleRegister            = 0x06
      enc ReadExceptionStatus            = 0x07
      enc Diagnostics                    = 0x08
      enc GetCommEventCounter            = 0x0B
      enc GetCommEventLog                = 0x0C
      enc WriteMultipleCoils             = 0x0F
      enc WriteMultipleRegisters         = 0x10
      enc ReportSlaveID                  = 0x11
      enc ReadFileRecord                 = 0x14
      enc WriteFileRecord                = 0x15
      enc MaskWriteRegister              = 0x16
      enc ReadWriteMultipleRegisters     = 0x17
      enc ReadFIFOQueue                  = 0x18
      enc EncapsulatedInterfaceTransport = 0x2B
      enc (UserDefinedCode   code)       = code
      enc (ReservedCode      code)       = code
      enc (OtherCode         code)       = code
      enc (ExceptionCode fc)             = 0x80 + enc fc

  get = getWord8 >>= return ∘ dec
    where
      dec ∷ Word8 → FunctionCode
      dec 0x01 = ReadCoils
      dec 0x02 = ReadDiscreteInputs
      dec 0x03 = ReadHoldingRegisters
      dec 0x04 = ReadInputRegisters
      dec 0x05 = WriteSingleCoil
      dec 0x06 = WriteSingleRegister
      dec 0x07 = ReadExceptionStatus
      dec 0x08 = Diagnostics
      dec 0x0B = GetCommEventCounter
      dec 0x0C = GetCommEventLog
      dec 0x0F = WriteMultipleCoils
      dec 0x10 = WriteMultipleRegisters
      dec 0x11 = ReportSlaveID
      dec 0x14 = ReadFileRecord
      dec 0x15 = WriteFileRecord
      dec 0x16 = MaskWriteRegister
      dec 0x17 = ReadWriteMultipleRegisters
      dec 0x18 = ReadFIFOQueue
      dec 0x2B = EncapsulatedInterfaceTransport
      dec code | (code ≥  65 ∧ code ≤  72)
               ∨ (code ≥ 100 ∧ code ≤ 110) = UserDefinedCode code
               | code ∈ [9, 10, 13, 14, 41, 42, 90, 91, 125, 126, 127]
                 = ReservedCode code
               | code ≥ 0x80 = ExceptionCode $ dec $ code - 0x80
               | otherwise = OtherCode code

-- | See: MODBUS Application Protocol Specification V1.1b, section 7
data ExceptionCode =
    -- | The function code received in the query is not an allowable
    -- action for the server (or slave). This may be because the
    -- function code is only applicable to newer devices, and was not
    -- implemented in the unit selected. It could also indicate that
    -- the server (or slave) is in the wrong state to process a
    -- request of this type, for example because it is unconfigured
    -- and is being asked to return register values.
    IllegalFunction
    -- | The data address received in the query is not an allowable
    -- address for the server (or slave). More specifically, the
    -- combination of reference number and transfer length is
    -- invalid. For a controller with 100 registers, the PDU addresses
    -- the first register as 0, and the last one as 99. If a request
    -- is submitted with a starting register address of 96 and a
    -- quantity of registers of 4, then this request will successfully
    -- operate (address-wise at least) on registers 96, 97, 98, 99. If
    -- a request is submitted with a starting register address of 96
    -- and a quantity of registers of 5, then this request will fail
    -- with Exception Code 0x02 \"Illegal Data Address\" since it
    -- attempts to operate on registers 96, 97, 98, 99 and 100, and
    -- there is no register with address 100.
  | IllegalDataAddress
    -- | A value contained in the query data field is not an allowable
    -- value for server (or slave). This indicates a fault in the
    -- structure of the remainder of a complex request, such as that
    -- the implied length is incorrect. It specifically does NOT mean
    -- that a data item submitted for storage in a register has a
    -- value outside the expectation of the application program, since
    -- the MODBUS protocol is unaware of the significance of any
    -- particular value of any particular register.
  | IllegalDataValue
    -- | An unrecoverable error occurred while the server (or slave)
    -- was attempting to perform the requested action.
  | SlaveDeviceFailure
    -- | Specialized use in conjunction with programming commands. The
    -- server (or slave) has accepted the request and is processing
    -- it, but a long duration of time will be required to do so. This
    -- response is returned to prevent a timeout error from occurring
    -- in the client (or master). The client (or master) can next
    -- issue a Poll Program Complete message to determine if
    -- processing is completed.
  | Acknowledge
    -- | Specialized use in conjunction with programming commands. The
    -- server (or slave) is engaged in processing a long–duration
    -- program command. The client (or master) should retransmit the
    -- message later when the server (or slave) is free.
  | SlaveDeviceBusy
    -- | Specialized use in conjunction with function codes
    -- 'ReadFileRecord' and 'WriteFileRecord' and reference type 6, to
    -- indicate that the extended file area failed to pass a
    -- consistency check.
  | MemoryParityError
    -- | Specialized use in conjunction with gateways, indicates that
    -- the gateway was unable to allocate an internal communication
    -- path from the input port to the output port for processing the
    -- request. Usually means that the gateway is misconfigured or
    -- overloaded.
  | GatewayPathUnavailable
    -- | Specialized use in conjunction with gateways, indicates that
    -- no response was obtained from the target device. Usually means
    -- that the device is not present on the network.
  | GatewayTargetDeviceFailedToRespond
    deriving Show

instance Serialize ExceptionCode where
  put = putWord8 ∘ enc
    where
      enc IllegalFunction                    = 0x01
      enc IllegalDataAddress                 = 0x02
      enc IllegalDataValue                   = 0x03
      enc SlaveDeviceFailure                 = 0x04
      enc Acknowledge                        = 0x05
      enc SlaveDeviceBusy                    = 0x06
      enc MemoryParityError                  = 0x08
      enc GatewayPathUnavailable             = 0x0A
      enc GatewayTargetDeviceFailedToRespond = 0x0B

  get = getWord8 >>= dec
    where
      dec 0x01 = return IllegalFunction
      dec 0x02 = return IllegalDataAddress
      dec 0x03 = return IllegalDataValue
      dec 0x04 = return SlaveDeviceFailure
      dec 0x05 = return Acknowledge
      dec 0x06 = return SlaveDeviceBusy
      dec 0x08 = return MemoryParityError
      dec 0x0A = return GatewayPathUnavailable
      dec 0x0B = return GatewayTargetDeviceFailedToRespond
      dec _    = mzero

data MB_Exception = ExceptionResponse FunctionCode ExceptionCode
                  | DecodeException String
                  | OtherException String
                    deriving (Show, Typeable)

instance Exception MB_Exception

-- | Sends a raw MODBUS command.
command ∷ TransactionId
        → ProtocolId
        → UnitId
        → FunctionCode -- ^ PDU function code.
        → ByteString   -- ^ PDU data.
        → S.Socket
        → IO (Either MB_Exception TCP_ADU)
command tid pid uid fc fdata socket = do
    _ ← S.send socket $ encode cmd
    result ← S.recv socket 512
    return $ either (Left ∘ DecodeException) checkResponse $ decode result
  where
    cmd = TCP_ADU (Header tid pid (fromIntegral $ 2 + BS.length fdata) uid)
                  fc
                  fdata

-- | Checks whether the response contains an error.
checkResponse ∷ TCP_ADU → Either MB_Exception TCP_ADU
checkResponse adu@(TCP_ADU _ fc bs) =
    case fc of
      ExceptionCode rc → Left $ either DecodeException (ExceptionResponse rc)
                              $ decode bs
      _ → Right adu

readCoils ∷ TransactionId
          → ProtocolId
          → UnitId
          → Word16
          → Word16
          → S.Socket
          → IO (Either MB_Exception [Word8])
readCoils tid pid uid addr count socket =
    either Left
           ( either (Left ∘ DecodeException) Right
           ∘ runGet decodeW8s ∘ aduData
           )
           <$> command tid pid uid ReadCoils
                       (runPut $ putWord16be addr >> putWord16be count)
                       socket

readDiscreteInputs ∷ TransactionId
                   → ProtocolId
                   → UnitId
                   → Word16
                   → Word16
                   → S.Socket
                   → IO (Either MB_Exception [Word8])
readDiscreteInputs tid pid uid addr count socket =
    either Left
           ( either (Left ∘ DecodeException) Right
           ∘ runGet decodeW8s ∘ aduData
           )
           <$> command tid pid uid ReadDiscreteInputs
                       (runPut $ putWord16be addr >> putWord16be count)
                       socket

readHoldingRegisters ∷ TransactionId
                     → ProtocolId
                     → UnitId
                     → Word16 -- ^ Register starting address.
                     → Word16 -- ^ Quantity of registers.
                     → S.Socket
                     → IO (Either MB_Exception [Word16])
readHoldingRegisters tid pid uid addr count socket =
    either Left
           ( either (Left ∘ DecodeException) Right
           ∘ runGet decodeW16s ∘ aduData
           )
           <$> command tid pid uid ReadHoldingRegisters
                       (runPut $ putWord16be addr >> putWord16be count)
                       socket

readInputRegisters ∷ TransactionId
                   → ProtocolId
                   → UnitId
                   → Word16 -- ^ Starting address.
                   → Word16 -- ^ Quantity of input registers.
                   → S.Socket
                   → IO (Either MB_Exception [Word16])
readInputRegisters tid pid uid addr count socket =
    either Left
           ( either (Left ∘ DecodeException) Right
           ∘ runGet decodeW16s ∘ aduData
           )
           <$> command tid pid uid ReadInputRegisters
                       (runPut $ putWord16be addr >> putWord16be count)
                       socket

writeSingleCoil ∷ TransactionId
                → ProtocolId
                → UnitId
                → Word16
                → Bool
                → S.Socket
                → IO (Either MB_Exception ())
writeSingleCoil tid pid uid addr value socket = do
    resp ← command tid pid uid WriteSingleCoil
                   (runPut $ putWord16be addr >> putWord16be (if value then 0xFF00 else 0))
                   socket
    return $ either Left (const $ Right ()) resp

writeSingleRegister ∷ TransactionId
                    → ProtocolId
                    → UnitId
                    → Word16 -- ^ Register address.
                    → Word16 -- ^ Register value.
                    → S.Socket
                    → IO (Either MB_Exception ())
writeSingleRegister tid pid uid addr value socket = do
    resp ← command tid pid uid WriteSingleRegister
                   (runPut $ putWord16be addr >> putWord16be value)
                   socket
    return $ either Left (const $ Right ()) resp

writeMultipleRegisters ∷ TransactionId
                       → ProtocolId
                       → UnitId
                       → Word16 -- ^ Register starting address
                       → [Word16] -- ^ Register values to be written
                       → S.Socket
                       → IO (Either MB_Exception Word16)
writeMultipleRegisters tid pid uid addr values socket =
    either Left
           ( either (Left ∘ DecodeException) Right
           ∘ runGet (getWord16be >> getWord16be) ∘ aduData
           )
           <$> command tid pid uid WriteMultipleRegisters
                       ( runPut $ do
                           putWord16be addr
                           putWord16be $ fromIntegral numRegs
                           putWord8 $ fromIntegral numRegs
                           mapM_ putWord16be values
                       )
                       socket
  where
    numRegs ∷ Int
    numRegs = length values

--------------------------------------------------------------------------------

decodeW8s ∷ Get [Word8]
decodeW8s = do n ← getWord8
               replicateM (fromIntegral n) getWord8

decodeW16s ∷ Get [Word16]
decodeW16s = do n ← getWord8
                replicateM (fromIntegral $ n `div` 2) getWord16be

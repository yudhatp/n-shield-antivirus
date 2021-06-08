unit kpSHuge;

{ $Log: }


{ Secrets of Delphi 2, by Ray Lischner. (1996, Waite Group Press).
  Chapter 3: Streams and File I/O
  Copyright � 1996 The Waite Group, Inc. }

{ Manipulate huge pointers. Note that all uses of
  this unit are portable between Delphi 1 and Delphi 2,
  even though the implementation is not. }
  
interface

 {$IFNDEF WIN32}
 USES WinTypes, WinProcs;
 {$ENDIF}

  { HugeInc() and HugeOffset() add an offset to a far pointer.
    The offset can be greater than 64K, and the pointer's segment
    is properly updated. HugeDec decrements the pointer (which is
    the same as adding a negative increment). These routines all do
    (more or less) the same thing, but return the result
    differently. Choose whichever is more convenient.
  }
  procedure HugeInc(var HugePtr: Pointer; Amount: LongInt);
  procedure HugeDec(var HugePtr: Pointer; Amount: LongInt);
  function  HugeOffset(HugePtr: Pointer; Amount: LongInt): Pointer;

{$ifdef WIN32}
  { The Win3.1 API defines hmemcpy to copy memory that might span
    a segment boundary. Win32 does not define it, so add it, for portability. }
  procedure HMemCpy(DstPtr, SrcPtr: Pointer; Amount: LongInt);
{$else}
  { The Win32 API defines these functions, so they are needed only for Win3.1. }
  procedure ZeroMemory(Ptr: Pointer; Length: LongInt);
  procedure FillMemory(Ptr: Pointer; Length: LongInt; Fill: Byte);

 type
  bytearrayptr = ^bytearraytype;
  wordarrayptr = ^wordarraytype;
  bytearraytype = array[0..0] of Byte;
  wordarraytype = array[0..0] of Word;

  TkpHugeByteArray = class
  private
    FMemBlock: THandle;
    FSize: Longint;
    FLocked: Boolean;
    FAPtr: PByte;
    bytearray: bytearrayptr;

    procedure SetSize(NewSize: Longint);
    function GetItem(Index: Longint): Byte;
    procedure SetItem(Index: Longint; Value: Byte);
    procedure CheckSize(Value: Longint);
  protected
    function GetMaxSize: Longint; virtual;
    procedure UnlockBlock; virtual;
    procedure SetLock(Value: Boolean); virtual;
    function GetAddrOf(Index: LongInt): PByte; virtual;
  public
    constructor Create(ArraySize: Longint); virtual;
    destructor Destroy; override;
    property Size: Longint read FSize write SetSize;
    property Locked: Boolean read FLocked write SetLock;
    property AddrOf[Index: Longint]: PByte read GetAddrOf;
    property Items[Index: Longint]: Byte read GetItem write SetItem; default;
  end;

  TkpHugeWordArray = class
  private
    FMemBlock: THandle;
    FSize: Longint;
    FLocked: Boolean;
    FAPtr: PWord;
    wordarray: wordarrayptr;

    procedure SetSize(NewSize: Longint);
    function GetItem(Index: Longint): Word;
    procedure SetItem(Index: Longint; Value: Word);
    procedure CheckSize(Value: Longint);
  protected
    function GetMaxSize: Longint; virtual;
    procedure UnlockBlock; virtual;
    procedure SetLock(Value: Boolean); virtual;
    function GetAddrOf(Index: LongInt): PWord; virtual;
  public
    constructor Create(ArraySize: Longint); virtual;
    destructor Destroy; override;
    property Size: Longint read FSize write SetSize;
    property Locked: Boolean read FLocked write SetLock;
    property AddrOf[Index: Longint]: PWord read GetAddrOf;
    property Items[Index: Longint]: Word read GetItem write SetItem; default;
  end;


{$endif}

implementation

{$ifdef WIN32}
procedure HugeInc(var HugePtr: Pointer; Amount: LongInt);
begin
  HugePtr := PChar(HugePtr) + Amount;
end;

procedure HugeDec(var HugePtr: Pointer; Amount: LongInt);
begin
  HugePtr := PChar(HugePtr) - Amount;
end;

function  HugeOffset(HugePtr: Pointer; Amount: LongInt): Pointer;
begin
  Result := PChar(HugePtr) + Amount;
end;

{ This is not defined in Delphi 2.0. }
procedure HMemCpy(DstPtr, SrcPtr: Pointer; Amount: LongInt);
begin
  Move(SrcPtr^, DstPtr^, Amount);
end;
{$else}

uses SysUtils;

const
  MemAllocFlags: word = gmem_Moveable or gmem_Discardable;

procedure HugeShift; far; external 'KERNEL' index 113;

{ Increment a huge pointer. }
{ Pascal equivalent for HugeInc:
  Inc(Amount, LongRec(HugePtr).Lo);
  Inc(LongRec(HugePtr).Hi, SelectorInc * LongRec(Amount).Hi);
  LongRec(HugePtr).Lo := LongRec(Amount).Lo;
}
procedure HugeInc(var HugePtr: Pointer; Amount: LongInt); assembler;
asm
  mov ax, Amount.Word[0]    { Store Amount in DX:AX. }
  mov dx, Amount.Word[2]
  les bx, HugePtr           { Get the reference to HugePtr. }
  add ax, es:[bx]           { Add the offset parts. }
  adc dx, 0                 { Propagate carry to the high word of Amount. }
  mov cx, Offset HugeShift
  shl dx, cl                { Shift high word of Amount for segment. }
  add es:[bx+2], dx         { Increment the segment of HugePtr. }
  mov es:[bx], ax
end;

{ Decrement a huge pointer. }
procedure HugeDec(var HugePtr: Pointer; Amount: LongInt); assembler;
asm
  les bx, HugePtr         { Store HugePtr ptr in es:[bx] }
  mov ax, es:[bx]
  sub ax, Amount.Word[0]  { Subtract the offset parts }
  mov dx, Amount.Word[2]
  adc dx, 0               { Propagate carry to the high word of Amount }
  mov cx, OFFSET HugeShift
  shl dx, cl              { Shift high word of Amount for segment }
  sub es:[bx+2], dx
  mov es:[bx], ax
end;

{ Add an offset to a huge pointer and return the result. }
function HugeOffset(HugePtr: Pointer; Amount: LongInt): Pointer; assembler;
asm
  mov ax, Amount.Word[0]  { Store Amount in DX:AX }
  mov dx, Amount.Word[2]
  add ax, HugePtr.Word[0] { Add the offset parts }
  adc dx, 0               { Propagate carry to the high word of Amount }
  mov cx, OFFSET HugeShift
  shl dx, cl              { Shift high word of Amount for segment }
  add dx, HugePtr.Word[2] { Increment the segment of HugePtr }
end;

{ When setting the Count, one might add many new items, which
  must be set to zero at one time, to initialize all items to nil.
  You could use FillChar, which fills by bytes, but, as DoMove
  is to Move, ZeroBytes is to FillChar, except that it always
  fill with zero valued words. }
procedure FillWords(DstPtr: Pointer; Size: Word; Fill: Word); assembler;
asm
  mov ax, Fill            { Get the fill word. }
  les di, DstPtr          { Get the pointer. }
  mov cx, Size.Word[0]    { Get the size. }
  cld                     { Clear the direction flag. }
  rep stosw               { Fill the memory. }
end;

{ Fill Length bytes of memory with Fill, starting at Ptr.
  This is just like the procedure in the Win32 API. The memory
  can be larger than 64K and can cross segment boundaries. }

procedure FillMemory(Ptr: Pointer; Length: LongInt; Fill: Byte);
var
  NBytes: Cardinal;
  NWords: Cardinal;
  FillWord: Word;
begin
  WordRec(FillWord).Hi := Fill;
  WordRec(FillWord).Lo := Fill;
  while Length > 1 do
  begin
    { Determine the number of bytes remaining in the segment. }
    if Ofs(Ptr^) = 0 then
      NBytes := $FFFE
    else
      NBytes := $10000 - Ofs(Ptr^);
    if NBytes > Length then
      NBytes := Length;
    { Filling by words is faster than filling by bytes. }
    NWords := NBytes div 2;
    FillWords(Ptr, NWords, FillWord);
    NBytes := NWords * 2;
    Dec(Length, NBytes);
    Ptr := HugeOffset(Ptr, NBytes);
  end;
  { If the fill size is odd, then fill the remaining byte. }
  if Length > 0 then
    PByte(Ptr)^ := Fill;
end;

procedure ZeroMemory(Ptr: Pointer; Length: LongInt);
begin
  FillMemory(Ptr, Length, 0);
end;

{********************** Huge Byte ***************************}
constructor TkpHugeByteArray.Create(ArraySize: Longint);
begin
  FLocked := False;
  if ArraySize > GetMaxSize then
    ArraySize := GetMaxSize;
  FMemBlock := GlobalAlloc(MemAllocFlags, ArraySize * SizeOf(Byte));
  if FMemBlock <> 0 then
    FSize := ArraySize
  else
    raise EOutOfMemory.Create('Couldn''t allocate memory block.');
  FAPtr := GlobalLock(FMemBlock);
  FLocked := True;
  bytearray := bytearrayptr(FAPtr);
end;

destructor TkpHugeByteArray.Destroy;
begin
  inherited Destroy;
  UnlockBlock;
  SetLock(False);
  if GlobalFree(FMemBlock) <> 0 then
    raise EInvalidPointer.Create('Couln''t free memory block');
end;

function TkpHugeByteArray.GetMaxSize: Longint;
begin
  Result := MaxLongint;
end;

procedure TkpHugeByteArray.SetSize(NewSize: Longint);
begin
  if NewSize <> FSize then begin
    if NewSize > GetMaxSize then
      NewSize := GetMaxSize;
    if GlobalReAlloc(FMemBlock, NewSize * SizeOf(Byte), MemAllocFlags) <> 0
        then
      FSize := NewSize
    else
      raise EOutOfMemory.Create('Couln''t realloc memory block');
  end;
end;

procedure TkpHugeByteArray.SetLock(Value: Boolean);
begin
  exit;
  if FLocked <> Value then begin
    if Value then begin
      GlobalLock(FMemBlock);
      FLocked := True;
    end
    else begin
      FLocked := False;
      UnlockBlock;
    end;
  end;
end;

function TkpHugeByteArray.GetAddrOf(Index: Longint): PByte;
begin
  Result := @bytearray^[Index];
end;

procedure TkpHugeByteArray.UnlockBlock;
begin
  if not FLocked then GlobalUnlock(FMemBlock);
end;

procedure TkpHugeByteArray.CheckSize(Value: Longint);
begin
  if (Value > FSize) or (Value < 0) then
    raise ERangeError.Create('Index not within established range.');
end;

procedure TkpHugeByteArray.SetItem(Index: Longint; Value: Byte);
begin
  bytearray^[Index] := Value;
end;

function TkpHugeByteArray.GetItem(Index: Longint): Byte;
begin
  Result := bytearray^[Index];
end;

{********************** Huge Word ***************************}
constructor TkpHugeWordArray.Create(ArraySize: Longint);
begin
  FLocked := False;
  if ArraySize > GetMaxSize then
    ArraySize := GetMaxSize;
  FMemBlock := GlobalAlloc(MemAllocFlags, ArraySize * SizeOf(Word));
  if FMemBlock <> 0 then
    FSize := ArraySize
  else
    raise EOutOfMemory.Create('Couldn''t allocate memory block.');
  FAPtr := GlobalLock(FMemBlock);
  FLocked := True;
  wordarray := wordarrayptr(FAPtr);
end;

destructor TkpHugeWordArray.Destroy;
begin
  inherited Destroy;
  UnlockBlock;
  SetLock(False);
  if GlobalFree(FMemBlock) <> 0 then
    raise EInvalidPointer.Create('Couln''t free memory block');
end;

function TkpHugeWordArray.GetMaxSize: Longint;
begin
  Result := MaxLongint div SizeOf(Word);
end;

procedure TkpHugeWordArray.SetSize(NewSize: Longint);
begin
  if NewSize <> FSize then begin
    if NewSize > GetMaxSize then
      NewSize := GetMaxSize;
    if GlobalReAlloc(FMemBlock, NewSize * SizeOf(Word), MemAllocFlags) <> 0
        then
      FSize := NewSize
    else
      raise EOutOfMemory.Create('Couln''t realloc memory block');
  end;
end;

procedure TkpHugeWordArray.SetLock(Value: Boolean);
begin
  if FLocked <> Value then begin
    if Value then begin
      GlobalLock(FMemBlock);
      FLocked := True;
    end
    else begin
      FLocked := False;
      UnlockBlock;
    end;
  end;
end;

function TkpHugeWordArray.GetAddrOf(Index: Longint): PWord;
begin
  Result := @wordarray^[Index];
end;

procedure TkpHugeWordArray.UnlockBlock;
begin
  if not FLocked then GlobalUnlock(FMemBlock);
end;

procedure TkpHugeWordArray.CheckSize(Value: Longint);
begin
  if (Value > FSize) or (Value < 0) then
    raise ERangeError.Create('Index not within established range.');
end;

procedure TkpHugeWordArray.SetItem(Index: Longint; Value: Word);
begin
  wordarray^[Index] := Value;
end;

function TkpHugeWordArray.GetItem(Index: Longint): Word;
begin
  Result := wordarray^[Index];
end;



{$endif}

end.

program GxtToolUnicode;

{
  GXT<=>TXT converter for GTA2
  by Daniel Marschall
  Revision: 26 April 2026
  Licensed under the terms of the Apache 2.0 license
  Source code compatible with Delphi for Win32/64, and FreePascal for Debian Linux
  More information here: https://misc.daniel-marschall.de/spiele/gta2/
}

// TODO: ... see more TODOs below
// TODO: Implement/Research Russian
// TODO: Implement/Research Japanese Kanji Validation
// TODO: Test FPC

{$IFDEF FPC}
  {$mode delphi}
  {$H+}
{$ELSE}
  {$APPTYPE CONSOLE}

{$ENDIF}

{$IFDEF FPC}
uses
  SysUtils,
  Classes,
  baseunix,
  ctypes;
{$ELSE}
{$R *.dres}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  WinApi.Windows;

{$ENDIF}

resourcestring
  S_INVALID_PARAM = 'Invalid parameter/file';
  S_INVALID_FILE = 'File is neither TXT nor GXT';
  S_ERR_S_S = 'ERROR (%s): %s';
  S_WARN_S_S = 'WARNING (%s): %s';
  S_OK_S_S = 'OK: %s => %s';
  {$IFDEF MSWINDOWS}
  S_PRESS_ANY_KEY = 'Press any key to exit.';
  {$ENDIF}
  S_INTRO_1 = 'GXT<>TXT Converter for GTA 2 (Unicode Version)';
  S_INTRO_2 = 'by Daniel Marschall';
  S_INTRO_3 = 'Revision: 26 April 2026';
  S_INTRO_4 = 'Licensed under the terms of the Apache 2.0 license';
  S_USAGE = 'Usage:';
  S_IllegalKanji = 'Warning: Illegal character not in Kanji.dat: %s';
  S_IllegalEuropeanChar = 'Warning: Illegal European character: %s';

// --- Encoding Stuff

const
  CP_UTF8 = 65001;
  CP_EURO = 1252;
  CP_SJIS = 932;

function MakeEncoding(CodePage: Integer): TEncoding;
begin
  Result := TEncoding.GetEncoding(CodePage);
end;

function ConvertEncoding(const Data: TBytes; SrcCodePage, DstCodePage: Integer): TBytes;
var
  SrcEnc, DstEnc: TEncoding;
  TempString: string;
begin
  SrcEnc := TEncoding.GetEncoding(SrcCodePage);
  DstEnc := TEncoding.GetEncoding(DstCodePage);

  try
    TempString := SrcEnc.GetString(Data);   // bytes -> Unicode
    Result := DstEnc.GetBytes(TempString); // Unicode -> bytes
  finally
    SrcEnc.Free;
    DstEnc.Free;
  end;
end;

function StringToRawBytes(const S: string): TBytes;
var
  Len: Integer;
begin
  Len := Length(S) * SizeOf(Char); // Char = WideChar = 2 bytes

  SetLength(Result, Len);

  if Len > 0 then
    Move(PChar(S)^, Result[0], Len);
end;

{$IFDEF FPC}
type
  iconv_t = Pointer;

function iconv_open(tocode, fromcode: PChar): iconv_t; cdecl; external 'c';
function iconv(cd: iconv_t; inbuf: PPChar; inbytesleft: PSizeUInt; outbuf: PPChar; outbytesleft: PSizeUInt): SizeUInt; cdecl; external 'c';
function iconv_close(cd: iconv_t): cint; cdecl; external 'c';

function ConvertWithIconv(const Data: TBytes; SourceEncoding, TargetEncoding: TEncoding): TBytes;

  function EncodingToIconvName(Enc: TEncoding): string;
  begin
    if Enc.CodePage = 65001 then Exit('UTF-8');
    if Enc.CodePage = 932 then Exit('CP932');
    if Enc.CodePage = 1252 then Exit('CP1252');
    raise Exception.Create('Unsupported encoding: ' + IntToStr(Enc.CodePage));
  end;

var
  cd: iconv_t;
  InBuf, OutBuf: PAnsiChar;
  InBytesLeft, OutBytesLeft: SizeUInt;
  OutSize: SizeUInt;
  PIn, POut: PAnsiChar;
  FromEnc, ToEnc: string;
begin
  Result := nil;

  FromEnc := EncodingToIconvName(SourceEncoding);
  ToEnc := EncodingToIconvName(TargetEncoding);

  cd := iconv_open(PChar(ToEnc), PChar(FromEnc));
  if cd = iconv_t(-1) then
    raise Exception.Create('iconv_open failed');

  try
    InBytesLeft := Length(Data);
    OutSize := InBytesLeft * 4 + 16;

    SetLength(Result, OutSize);

    PIn := PAnsiChar(@Data[0]);
    POut := PAnsiChar(@Result[0]);

    InBuf := PIn;
    OutBuf := POut;
    OutBytesLeft := OutSize;

    while InBytesLeft > 0 do
    begin
      if iconv(cd, @InBuf, @InBytesLeft, @OutBuf, @OutBytesLeft) = SizeUInt(-1) then
        raise Exception.Create('iconv failed. File has probably invalid characters.');
    end;

    SetLength(Result, OutSize - OutBytesLeft);
  finally
    iconv_close(cd);
  end;
end;
{$ENDIF}

// --- Read File Methods

function ReadAllBytesFromFile(const FileName: string): TBytes;
{$IFDEF FPC}
var
  FS: TFileStream;
begin
  Result := nil; // SetLength(Result, 0);
  if not FileExists(FileName) then
    raise Exception.CreateFmt('File not found: %s', [FileName]);

  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, FS.Size);
    if FS.Size > 0 then
      FS.ReadBuffer(Result[0], FS.Size);
  finally
    FreeAndNil(FS);
  end;
{$ELSE}
begin
  Result := TFile.ReadAllBytes(FileName);
{$ENDIF}
end;

function ReadTextFileWithEncoding(const FileName: string; const SourceEncoding: TEncoding; const TargetEncoding: TEncoding): TBytes;
{$IFDEF FPC}

  function RemovePreamble(const Bytes: TBytes; const Encoding: TEncoding): TBytes;
  var
    Preamble: TBytes;
    I: Integer;
    Matches: Boolean;
  begin
    Result := Bytes;
    Preamble := Encoding.GetPreamble;
    if Length(Preamble) = 0 then
      Exit;
    if Length(Bytes) < Length(Preamble) then
      Exit;
    Matches := True;
    for I := 0 to High(Preamble) do
    begin
      if Bytes[I] <> Preamble[I] then
      begin
        Matches := False;
        Break;
      end;
    end;
    if Matches then
      Result := Copy(Bytes, Length(Preamble), Length(Bytes) - Length(Preamble));
  end;

var
  B: TBytes;
begin
  B := ReadAllBytesFromFile(FileName);
  B := RemovePreamble(B, SourceEncoding);
  Result := ConvertWithIconv(B, SourceEncoding, TargetEncoding);

{$ELSE}
begin
  Result := TargetEncoding.GetBytes(TFile.ReadAllText(FileName, SourceEncoding));
{$ENDIF}
end;

// --- Write File Methods

procedure WriteAllBytesToFile(const FileName: string; Data: TBytes);
{$IFDEF FPC}
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(FileName, fmCreate);
  try
    if Length(Data) > 0 then
      FS.WriteBuffer(Data[0], Length(Data));
  finally
    FreeAndNil(FS);
  end;
{$ELSE}
begin
  TFile.WriteAllBytes(FileName, Data);
{$ENDIF}
end;

procedure WriteTextFileWithEncoding(const FileName: string; const SourceEncoding: TEncoding; const TargetEncoding: TEncoding; const Data: TBytes);
{$IFDEF FPC}
  function PrependBytes(const Prefix, Data: TBytes): TBytes;
  var
    PrefixLen, DataLen: Integer;
  begin
    Result := nil;

    PrefixLen := Length(Prefix);
    DataLen := Length(Data);

    SetLength(Result, PrefixLen + DataLen);

    if PrefixLen > 0 then
      Move(Prefix[0], Result[0], PrefixLen);

    if DataLen > 0 then
      Move(Data[0], Result[PrefixLen], DataLen);
  end;

var
  ConvertedBytes: TBytes;
begin
  ConvertedBytes := ConvertWithIconv(Data, SourceEncoding, TargetEncoding);
  ConvertedBytes := PrependBytes(TargetEncoding.GetPreamble, ConvertedBytes);
  WriteAllBytesToFile(FileName, ConvertedBytes);
{$ELSE}
begin
  TFile.WriteAllText(FileName, SourceEncoding.GetString(Data), TargetEncoding);
{$ENDIF}
end;

// --- File Detection

type
  TFileEncInfo = record
    IsUtf8: Boolean;
    IsJapanese: Boolean;
    Encoding: TEncoding;
    FileEncoding: TEncoding; // for reading the file
  end;

// Decode UTF-8 sequence and check for CJK (U+3000..U+9FFF, U+F900..U+FAFF)
function IsCJKCodepoint(CP: Cardinal): Boolean;
begin
  Result := ((CP >= $3000) and (CP <= $9FFF)) or
            ((CP >= $F900) and (CP <= $FAFF));
end;

function DetectFileEncoding(const FileName: string): TFileEncInfo;
var
  RawBytes, Sample: TBytes;
  I: Integer;
  HasBOM, IsShiftJIS, HasCJK: Boolean;
  B, B2: Byte;
  CodePoint: Cardinal;
  SJISBytes: Integer;
begin
  Result.IsUtf8 := False;
  Result.IsJapanese := False;
  Result.Encoding := MakeEncoding(CP_EURO);
  Result.FileEncoding := MakeEncoding(CP_EURO);

  RawBytes := ReadAllBytesFromFile(FileName);
  if Length(RawBytes) = 0 then
    Exit;

  // Sample: First 8 KB is enough for heuristics
  if Length(RawBytes) < 8192 then
    SetLength(Sample, Length(RawBytes))
  else
    SetLength(Sample, 8192);
  Move(RawBytes[0], Sample[0], Length(Sample));

  // --- 1. Check BOM ---
  HasBOM := (Length(Sample) >= 3) and
            (Sample[0] = $EF) and (Sample[1] = $BB) and (Sample[2] = $BF);

  if HasBOM then
  begin
    // UTF-8 with BOM: Check contents for CJK
    Result.IsUtf8 := True;
    HasCJK := False;
    I := 3;
    while I < Length(Sample) - 2 do
    begin
      B := Sample[I];
      // 3-Byte UTF-8: $E3..$E9 → CJK-Area
      if (B >= $E3) and (B <= $E9) and
         ((Sample[I+1] and $C0) = $80) and
         ((Sample[I+2] and $C0) = $80) then
      begin
        CodePoint := ((Cardinal(B) and $0F) shl 12) or
                     ((Cardinal(Sample[I+1]) and $3F) shl 6) or
                      (Cardinal(Sample[I+2]) and $3F);
        if IsCJKCodepoint(CodePoint) then
        begin
          HasCJK := True;
          Break;
        end;
      end;
      Inc(I);
    end;
    Result.IsJapanese := HasCJK;
    Result.FileEncoding := MakeEncoding(CP_UTF8);
    if HasCJK then
      Result.Encoding := MakeEncoding(CP_SJIS)
    else
      Result.Encoding := MakeEncoding(CP_EURO);
    Exit;
  end;

  // --- 2. Detect Shift-JIS ---
  // Shift-JIS Lead-Bytes: $81-$9F or $E0-$EF, Trail: $40-$FC (except $7F)
  SJISBytes := 0;
  I := 0;
  while I < Length(Sample) - 1 do
  begin
    B := Sample[I];
    B2 := Sample[I + 1];
    if (((B >= $81) and (B <= $9F)) or ((B >= $E0) and (B <= $EF))) and
       ((B2 >= $40) and (B2 <= $FC) and (B2 <> $7F)) then
    begin
      Inc(SJISBytes, 2);
      Inc(I); // Skip second byte
    end;
    Inc(I);
  end;

  IsShiftJIS := (SJISBytes > Length(Sample) div 5); // >20%

  if IsShiftJIS then
  begin
    Result.IsJapanese := True;
    Result.Encoding := MakeEncoding(CP_SJIS);
    Result.FileEncoding := MakeEncoding(CP_SJIS);
    Exit;
  end;

  // --- 3. Detect UTF-8 without BOM ---
  Result.IsUtf8 := False;
  HasCJK := False;
  I := 0;
  while I < Length(Sample) - 2 do
  begin
    B := Sample[I];
    // 2-Byte: $C2-$DF
    if (B >= $C2) and (B <= $DF) and ((Sample[I+1] and $C0) = $80) then
    begin
      Result.IsUtf8 := True;
      Inc(I, 2);
      Continue;
    end;
    // 3-Byte: $E0-$EF → check for CJK
    if (B >= $E0) and (B <= $EF) and
       ((Sample[I+1] and $C0) = $80) and
       ((Sample[I+2] and $C0) = $80) then
    begin
      Result.IsUtf8 := True;
      CodePoint := ((Cardinal(B) and $0F) shl 12) or
                   ((Cardinal(Sample[I+1]) and $3F) shl 6) or
                    (Cardinal(Sample[I+2]) and $3F);
      if IsCJKCodepoint(CodePoint) then
        HasCJK := True;
      Inc(I, 3);
      Continue;
    end;
    Inc(I);
  end;

  if Result.IsUtf8 then
  begin
    Result.IsJapanese := HasCJK;
    Result.FileEncoding := MakeEncoding(CP_UTF8);
    if HasCJK then
      Result.Encoding := MakeEncoding(CP_SJIS)
    else
      Result.Encoding := MakeEncoding(CP_EURO);
    Exit;
  end;

  // --- 4. ANSI Fallback: only Byte-Statistics ---
  // Middle European ANSI: $80-$FF without Shift-JIS-Pattern → CP1252
  // (IsJapanese stays False, Encoding stays 1252)
end;

// --- Japanese Kanji Methods

function LoadKanjiDat: TBytes;
{$IFDEF FPC}
var
  FileName: string;
begin
  FileName := ExtractFilePath(ParamStr(0)) + 'kanji.dat'; // do not localize
  Result := ReadAllBytesFromFile(FileName);
  if (Length(Result) > 0) and ((Length(Result) mod 2) <> 0) then
    raise Exception.CreateFmt('Invalid kanji.dat size: %s', [FileName]);
{$ELSE}
var
  ResStream: TResourceStream;
begin
  ResStream := TResourceStream.Create(HInstance, 'KANJI_DAT', RT_RCDATA); // do not localize
  try
    SetLength(Result, ResStream.Size);
    ResStream.ReadBuffer(Result[0], ResStream.Size);
  finally
    FreeAndNil(ResStream);
  end;
{$ENDIF}
end;

function IsKanjiValid(const Data: TBytes; Value: Word): Boolean;
(*
var
  Offset: Integer;
  Entry: Word;
*)
begin
  Result := true; // TODO: Implement. First, find out how kanji.dat works
  (* GTA1 Kanji.idx worked like this:
  Offset := Value * 2;
  if Offset + 1 >= Length(Data) then
    Exit(False);
  Entry := PWord(@Data[Offset])^;
  Result := Entry <> $FFFF;
  *)
end;

// --- GTA2 Specific

const
  MAX_KEY_SIZE = 8;
  GXT_MAGIC = 'GBL';
  GXT_VER = 100;
  EU_Charset_Convert: array[0..48,0..1] of WideChar = (
        (#$80, #$C0),
        (#$81, #$C1),
        (#$82, #$C2),
        (#$83, #$C4),
        (#$84, #$C6),
        (#$85, #$C7),
        (#$86, #$C8),
        (#$87, #$C9),
        (#$88, #$CA),
        (#$89, #$CB),
        (#$8A, #$CC),
        (#$8B, #$CD),
        (#$8C, #$CE),
        (#$8D, #$CF),
        (#$8E, #$D2),
        (#$8F, #$D3),
        (#$90, #$D4),
        (#$91, #$D6),
        (#$92, #$D9),
        (#$93, #$DA),
        (#$94, #$DB),
        (#$95, #$DC),
        (#$96, #$DF),
        (#$97, #$E0),
        (#$98, #$E1),
        (#$99, #$E2),
        (#$9A, #$E4),
        (#$9B, #$E6),
        (#$9C, #$E7),
        (#$9D, #$E8),
        (#$9E, #$E9),
        (#$9F, #$EA),
        (#$A0, #$EB),
        (#$A1, #$EC),
        (#$A2, #$ED),
        (#$A3, #$EE),
        (#$A4, #$EF),
        (#$A5, #$F2),
        (#$A6, #$F3),
        (#$A7, #$F4),
        (#$A8, #$F6),
        (#$A9, #$F9),
        (#$AA, #$FA),
        (#$AB, #$FB),
        (#$AC, #$FC),
        (#$AD, #$D1),
        (#$AE, #$F1),
        (#$AF, #$BF),
        (#$B0, #$A1)
  );

type
  TGTAMessage = record
    key: AnsiString;
    guy: AnsiChar;
    msg: WideString;
  end;
  TGTAMessagesArray = array of TGTAMessage;

  TGXTHeader = packed record
    magic: array[0..2] of AnsiChar; // always "GBL"
    lang: AnsiChar; // E,G,F,I,S,J
    version: word // always 64 00 = 100
  end;

  TGXTSectionHeader = packed record
    sectionKey: array[0..3] of AnsiChar; // TKEY or TDAT
    sectionLength: Cardinal;
  end;

  TKEY = packed record
    relDataOffset: Cardinal;
    key: array[0..MAX_KEY_SIZE-1] of AnsiChar;
  end;


// --- GXT/TXT Converter Methods

procedure GxtToTxt(const InFile, OutFile: string);





  function GTA2toANSI_J(s: WideString): WideString;
  var
    i: Integer;
    w: Word;
    b: TBytes;
    enc: TEncoding;
  begin
    Result := '';
    enc := TEncoding.GetEncoding(932); // CP932 / Shift-JIS

    try
      for i := 1 to Length(s) do
      begin
        w := Word(s[i]);

        { ASCII / normal UTF-16 low chars }
        if w <= $007F then
        begin
          Result := Result + WideChar(w);
        end
        else
        begin
          { treat WideChar as packed SJIS bytes }
          SetLength(b, 2);
          b[0] := Byte(w shr 8);   // high byte
          b[1] := Byte(w and $FF); // low byte

          { if first byte zero -> single byte }
          if b[0] = 0 then
            SetLength(b, 1);

          Result := Result + enc.GetString(b);
        end;
      end;
    finally
      enc.Free;
    end;
  end;

  function GTA2toANSI_EU(s: WideString): WideString;
  var
    i, j: integer;
  begin
    result := s;
    for i := 1 to Length(s) do
    begin
      for j := Low(EU_Charset_Convert) to High(EU_Charset_Convert) do
      begin
        if result[i] = EU_Charset_Convert[j][0] then
        begin
          result[i] := EU_Charset_Convert[j][1];
          break;
        end;
      end;
    end;
  end;

  type
    TDecodeGXTAnswer = record
      Language: AnsiChar;
      Messages: TGTAMessagesArray;
    end;

  function DecodeGXT(fs: TFileStream): TDecodeGXTAnswer;
  var
    numEntries: integer;
    i: integer;
    filHead: TGXTHeader;
    tkAry: array of TKEY;
    tkLen: integer;
    secHead: TGXTSectionHeader;
    ws: WideString;
    extra: integer;
    p: pByte;
    op: PWideChar;
    msgBytes: TBytes;
    len: integer;
    ap: PAnsiChar;
  begin
    fs.Position := 0;

    fs.Read(filHead, SizeOf(filHead));

    if filHead.magic <> GXT_MAGIC then
    begin
      raise Exception.Create('ERROR: Magic header "'+GXT_MAGIC+'" missing.');
    end;
    result.Language := filHead.lang;
    if filHead.version <> GXT_VER then
    begin
      raise Exception.Create('ERROR: GXT version doesn''t has the value '+IntToStr(GXT_VER)+'.');
    end;
    fs.Seek(SizeOf(filHead), soFromBeginning);
    while fs.Position < fs.Size do
    begin
      fs.Read(secHead, SizeOf(secHead));
      if (secHead.sectionKey <> 'TKEY') and (secHead.sectionKey <> 'TDAT') then
      begin
        WriteLn('Attention: Unknown section type '+secHead.sectionKey);
      end;
      fs.Seek(secHead.sectionLength, soCurrent);
    end;
    extra := fs.Position - fs.Size;
    if extra > 0 then
    begin
      WriteLn('Attention: Extra bytes at end of file: ' + IntToStr(extra));
    end;

    // Step 1: Collect all keys
    fs.Seek(SizeOf(filHead), soFromBeginning);
    while fs.Position < fs.Size do
    begin
      fs.Read(secHead, SizeOf(secHead));
      if secHead.sectionKey = 'TKEY' then Break;
      fs.Seek(secHead.sectionLength, soCurrent);
    end;
    if secHead.sectionKey <> 'TKEY' then
    begin
      raise Exception.Create('ERROR: "TKEY" not found');
    end;
    tkLen := secHead.sectionLength;
    numEntries := tkLen div SizeOf(TKEY);
    SetLength(tkAry, numEntries);
    fs.Read(tkAry[0], tkLen);

    // Step 2: Collect all texts
    fs.Seek(SizeOf(filHead), soFromBeginning);
    while fs.Position < fs.Size do
    begin
      fs.Read(secHead, SizeOf(secHead));
      if secHead.sectionKey = 'TDAT' then Break;
      fs.Seek(secHead.sectionLength, soCurrent);
    end;
    if secHead.sectionKey <> 'TDAT' then
    begin
      raise Exception.Create('ERROR: "TDAT" not found');
    end;
    SetLength(ws, secHead.sectionLength div SizeOf(WideChar));
    fs.Read(ws[1], secHead.sectionLength);

    // Step 3: Generating output "messages" Variable
    op := PWideChar(ws);
    SetLength(result.Messages, numEntries);
    for i := 0 to numEntries-1 do
    begin



      p := PByte(op) + tkAry[i].relDataOffset;

      len := 0;

      { scan UTF-16 zero terminator #0#0 }
      while not ((p[len] = 0) and (p[len + 1] = 0)) do
        Inc(len, SizeOf(WideChar));

      SetLength(msgBytes, len);

      if Len > 0 then
        Move(p^, msgBytes[0], len);




      // Decode Speaker
      result.Messages[i].guy := #0;
      if Len > 1 then
      begin
        if msgBytes[1] = Ord('!') then
        begin
          result.Messages[i].guy := AnsiChar(msgBytes[0]);
          Move(msgBytes[2], msgBytes[0], Length(msgBytes) - 2);
          SetLength(msgBytes, Length(msgBytes) - 2);
        end;
      end;


      result.Messages[i].msg := TEncoding.Unicode.GetString(msgBytes);
      if filHead.lang = 'J' then
        result.Messages[i].msg := GTA2toANSI_J(result.Messages[i].msg)
      else
        result.Messages[i].msg := GTA2toANSI_EU(result.Messages[i].msg);

      ap := PAnsiChar(AnsiString(tkAry[i].key));
      result.Messages[i].key := ap;
    end;
  end;




var
  ans: TDecodeGXTAnswer;
  messages: TGTAMessagesArray;
  fs: TFileStream;
  i: integer;
  slOut: TStringList;
  speaker: string;
begin

  fs := TFileStream.Create(InFile, fmopenread);
  slOut := TStringList.Create;
  try
    ans := decodegxt(fs);
    messages := ans.Messages;
    // TODO: use this to help the GXT converter to choose the correct language
    //slOut.Add(format('[%s] %s', ['__LANG__', ans.Language]));
    for i := low(messages) to high(messages) do
    begin
      if messages[i].guy <> #0 then
      begin
        speaker := messages[i].guy + '!';
      end
      else
        speaker := '';

      slOut.Add(format('[%s] %s%s', [messages[i].key, speaker, messages[i].msg]));
    end;

    slOut.SaveToFile(Outfile, TEncoding.UTF8);

  finally
    FreeAndNil(fs);
  end;

  WriteLn(Format(S_OK_S_S, [InFile, OutFile]));
end;

procedure TxtToGxt(const InFile, OutFile: string; Language: Char);




  function ANSItoGTA2_J(s: WideString): WideString;
  var
    i: Integer;
    ch: WideString;
    b: TBytes;
    w: Word;
    enc: TEncoding;
  begin
    Result := '';
    enc := TEncoding.GetEncoding(932); // CP932 / Shift-JIS

    try
      for i := 1 to Length(s) do
      begin
        ch := s[i];

        { ASCII stays UTF-16 ASCII }
        if Ord(ch[1]) <= $7F then
        begin
          Result := Result + WideChar(Ord(ch[1]));
        end
        else
        begin
          b := enc.GetBytes(ch);

          if Length(b) = 1 then
            w := b[0]
          else
            w := (Word(b[0]) shl 8) or Word(b[1]);

          Result := Result + WideChar(w);
        end;
      end;
    finally
      enc.Free;
    end;
  end;

  function ANSItoGTA2_EU(s: WideString): WideString;
  var
    i, j: integer;
  begin
    result := s;
    for i := 1 to Length(s) do
    begin
      for j := Low(EU_Charset_Convert) to High(EU_Charset_Convert) do
      begin
        if result[i] = EU_Charset_Convert[j][1] then
        begin
          result[i] := EU_Charset_Convert[j][0];
          break;
        end;
      end;
    end;
  end;


  function ZeroPad(s: string; len: integer): string;
  begin
    result := s;
    while Length(result) < len do result := result + #0;
  end;

  function EncodeGXT(messages: TGTAMessagesArray; fsOut: TFileStream; lang: Char): string;
  var
    i: integer;
    msg: WideString;
    guywc: WideChar;
    curoffset: Cardinal;
    curkey: AnsiString;
    msKey, msDat: TMemoryStream;
    gxtHead: TGXTHeader;
    secHead: TGXTSectionHeader;
  begin
    msKey := TMemoryStream.Create;
    msDat := TMemoryStream.Create;
    try
      msKey.Size := 0;
      msDat.Size := 0;
      for i := Low(messages) to High(messages) do
      begin
        if Length(messages[i].key) > 7 then
        begin
          WriteLn('Attention: Line was ignored because key was too long: ' + messages[i].key);
          Continue;
        end;

        curoffset := msDat.Position;
        msKey.Write(curoffset, SizeOf(curoffset));
        curkey := AnsiString(ZeroPad(string(messages[i].key), MAX_KEY_SIZE));
        msKey.Write(curkey[1], Length(curkey)*SizeOf(AnsiChar));

        if Language = 'J' then
          msg := ANSItoGTA2_J(messages[i].msg) + #0
        else
          msg := ANSItoGTA2_EU(messages[i].msg) + #0;

        if messages[i].guy <> #0 then
        begin
          guywc := WideChar(Ord(messages[i].guy) + Ord('!') shl 8);
          msg := guywc + msg;
        end;

        msDat.Write(msg[1], Length(msg) * SizeOf(WideChar));
      end;

      gxtHead.magic   := GXT_MAGIC;
      gxtHead.lang    := AnsiChar(lang);
      gxtHead.version := GXT_VER;
      fsOut.Write(gxtHead, SizeOf(gxtHead));

      secHead.sectionKey := 'TKEY';
      secHead.sectionLength := msKey.Size;
      fsOut.Write(secHead, SizeOf(secHead));
      msKey.Position := 0;
      fsOut.CopyFrom(msKey, msKey.Size);

      secHead.sectionKey := 'TDAT';
      secHead.sectionLength := msDat.Size;
      fsOut.Write(secHead, SizeOf(secHead));
      msDat.Position := 0;
      fsOut.CopyFrom(msDat, msDat.Size);
    finally
      FreeAndNil(msKey);
      FreeAndNil(msDat);
    end;
  end;


  function LineToMessage(line: string; var m: TGTAMessage): boolean;
  var
    p: integer;
    key: AnsiString;
    msg: string;
    guy: AnsiChar;
  begin
    result := false;

    if Trim(line) = '' then Exit;

    if (Copy(line, 1, 1) <> '[') then
    begin
      WriteLn('Attention: Invalid line was ignored: ' + line);
      Exit;
    end;

    p := Pos(']', line);
    key := AnsiString(Copy(line, 2, p-2));

    if (Copy(line, p+1, 1) <> ' ') then
    begin
      WriteLn('Error: Invalid line: ' + line);
      Exit;
    end;

    msg := Copy(line, p+2, Length(line)-p-1);

    if Copy(msg, 2, 1) = '!' then
    begin
      guy := AnsiChar(msg[1]);
      msg := Copy(msg, 3, Length(msg)-2);
    end
    else
      guy := #0;

    m.key := key;
    m.guy := guy;
    m.msg := msg;

    result := true;
  end;





{$IFDEF FPC}
  function DecodeFPC(const B: TBytes; Info: TFileEncInfo): UnicodeString;

    function BytesToRawString(const B: TBytes): RawByteString;
    begin
      if Length(B) > 0 then
        SetString(Result, PAnsiChar(@B[0]), Length(B))
      else
        Result := '';
    end;

  var
    S: RawByteString;
  begin
    S := BytesToRawString(B);

    if IsUtf8 then
      Result := UTF8Decode(S)
    else if IsJapanese then
      Result := UTF8Decode(CP932ToUTF8(S))
    else
      Result := UTF8Decode(ISO_8859_1ToUTF8(S));
  end;
{$ENDIF}

{$IFNDEF FPC}
  function DecodeDelphi(const B: TBytes; Info: TFileEncInfo): UnicodeString;
  var
    P: Integer;
    Len: Integer;
  begin
    if Length(B) = 0 then
      Exit('');

    P := 0;
    Len := Length(B);

    // UTF8 BOM überspringen
    if info.IsUtf8 and (Len >= 3) and
       (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
    begin
      P := 3;
      Dec(Len, 3);
    end;

    if Assigned(info.Encoding) then
      Result := info.Encoding.GetString(B, P, Len)
    else if info.IsUtf8 then
      Result := TEncoding.UTF8.GetString(B, P, Len)
    else if info.IsJapanese then
      Result := TEncoding.GetEncoding(932).GetString(B, P, Len)
    else
      Result := TEncoding.GetEncoding(28591).GetString(B, P, Len);
  end;
{$ENDIF}





var
  InBytes, OutBytes: TBytes;
  Value: Integer;
  IsJapanese: Boolean;
  Info: TFileEncInfo;
  Sjis: Word;
  KanjiIdx: TBytes;
  S: UnicodeString;
  slIn: TStringList;
  i: integer;
  m: TGTAMessage;
  messages: TGTAMessagesArray;
  fsOut: TFileStream;
begin
  Info := DetectFileEncoding(InFile);

  IsJapanese := Info.IsJapanese;
  if IsJapanese then
    KanjiIdx := LoadKanjiDat;
  InBytes := ReadTextFileWithEncoding(InFile, Info.FileEncoding, Info.Encoding);
  SetLength(OutBytes, Length(InBytes) * 2 + 16);





  slIn := TStringList.Create;
  slIn.LineBreak := sLineBreak;
{$IFDEF FPC}
  S := DecodeFPC(InBytes, Info);
{$ELSE}
  S := DecodeDelphi(InBytes, Info);
{$ENDIF}
  slIn.Text := S;



  for i := Low(S) to High(s) do
  begin
    Value := Ord(s[i]);
    if IsJapanese then
    begin
      Sjis := Value;
      if not IsKanjiValid(KanjiIdx, Sjis) then
        WriteLn(Format(S_IllegalKanji, ['0x' + IntToHex(Sjis, 4)]));
    end
  end;




  messages := nil;
  SetLength(messages,0);
  for i := 0 to slIn.Count - 1 do
  begin
    if not LineToMessage(slIn.Strings[i], m) then Continue;
    SetLength(messages, Length(messages)+1);
    messages[Length(messages)-1] := m;
  end;
  fsOut := TFileStream.Create(Outfile, fmCreate or fmOpenWrite);
  try
    EncodeGXT(messages, fsOut, Language);
  finally
    FreeAndNil(fsOut);
  end;



  WriteLn(Format(S_OK_S_S, [InFile, OutFile]));
end;

// --- Main Methods (CLI)

procedure ShowUsage;
begin
  Writeln(S_INTRO_1);
  Writeln(S_INTRO_2);
  Writeln(S_INTRO_3);
  Writeln(S_INTRO_4);
  Writeln('');
  Writeln(S_USAGE);
  {$IFDEF MSWINDOWS}
  Writeln('  '+UpperCase(ExtractFileName(ParamStr(0)))+' input.gxt');
  Writeln('  '+UpperCase(ExtractFileName(ParamStr(0)))+' input.txt');
  {$ELSE}
  Writeln('  ./'+ExtractFileName(ParamStr(0))+' input.gxt [outfile.txt]');
  Writeln('  ./'+ExtractFileName(ParamStr(0))+' input.txt [outfile.gxt]');
  {$ENDIF}
  Writeln;
end;

function CompareFiles(const File1, File2: string): Boolean;
const
  BufferSize = 64 * 1024; // 64 KB
var
  Stream1, Stream2: TFileStream;
  Buffer1, Buffer2: TBytes;
  Read1, Read2: Integer;
begin
  Result := False;

  if not FileExists(File1) then
  begin
    Writeln(Format('Error: File not found: %s', [File1]));
    Exit;
  end;

  if not FileExists(File2) then
  begin
    Writeln(Format('Error: File not found: %s', [File2]));
    Exit;
  end;

  Stream1 := TFileStream.Create(File1, fmOpenRead or fmShareDenyWrite);
  Stream2 := TFileStream.Create(File2, fmOpenRead or fmShareDenyWrite);
  try
    // Check file size first
    if Stream1.Size <> Stream2.Size then
    begin
      Writeln(Format('TEST FAILURE: File size differs: %s %d <> %s %d)',
        [File1, Stream1.Size, File2, Stream2.Size]));
      Exit;
    end;

    SetLength(Buffer1, BufferSize);
    SetLength(Buffer2, BufferSize);

    repeat
      Read1 := Stream1.Read(Buffer1[0], BufferSize);
      Read2 := Stream2.Read(Buffer2[0], BufferSize);

      if Read1 <> Read2 then
      begin
        Writeln('TEST FAILURE: File contents differ '+File1+' <=> '+File2);
        Exit;
      end;

      if not CompareMem(@Buffer1[0], @Buffer2[0], Read1) then
      begin
        Writeln('TEST FAILURE: File contents differ '+File1+' <=> '+File2);
        Exit;
      end;
    until Read1 = 0;

    WriteLn('OK: (Binary comparison '+File1+' <=> '+File2+')');
    Result := True;
  finally
    FreeAndNil(Stream1);
    FreeAndNil(Stream2);
  end;
end;

procedure Testcases;
const
  {$IFDEF MSWINDOWS}
  TestDir = 'gxt_original\';
  {$ELSE}
  TestDir = 'gxt_original/';
  {$ENDIF}
begin
  GxtToTxt(TestDir + 'e.gxt', TestDir + 'e.txt');
  TxtToGxt(TestDir + 'e.txt', TestDir + 'e2.gxt', 'E');
  GxtToTxt(TestDir + 'e2.gxt', TestDir + 'e2.txt');
  CompareFiles(TestDir + 'e.txt', TestDir + 'e2.txt');
  //CompareFiles(TestDir + 'e.gxt', TestDir + 'e2.gxt');

  GxtToTxt(TestDir + 'j.gxt', TestDir + 'j.txt');
  TxtToGxt(TestDir + 'j.txt', TestDir + 'j2.gxt', 'J');
  GxtToTxt(TestDir + 'j2.gxt', TestDir + 'j2.txt');
  CompareFiles(TestDir + 'j.txt', TestDir + 'j2.txt');
  //CompareFiles(TestDir + 'j.gxt', TestDir + 'j2.gxt');

  // TODO: More testcases

  {$IFDEF MSWINDOWS}
  WriteLn(S_PRESS_ANY_KEY);
  ReadLn;
  exit;
  {$ENDIF}
end;

{$IFDEF MSWINDOWS}
procedure ProcessFile(const InFile: string; var RequirePause: boolean);
var
  Lang: Char;
begin
  try
    Lang := 'E'; // TODO: Determine language or ask the user
         if ExtractFileExt(InFile)         = '.gxt'  then GxtToTxt(InFile, ChangeFileExt(InFile, '.txt'))
    else if ExtractFileExt(InFile)         = '.GXT'  then GxtToTxt(InFile, ChangeFileExt(InFile, '.TXT'))
    else if SameText(ExtractFileExt(InFile), '.gxt') then GxtToTxt(InFile, ChangeFileExt(InFile, '.txt'))
    else if ExtractFileExt(InFile)         = '.txt'  then TxtToGxt(InFile, ChangeFileExt(InFile, '.gxt'), Lang)
    else if ExtractFileExt(InFile)         = '.TXT'  then TxtToGxt(InFile, ChangeFileExt(InFile, '.GXT'), Lang)
    else if SameText(ExtractFileExt(InFile), '.txt') then TxtToGxt(InFile, ChangeFileExt(InFile, '.gxt'), Lang)
    else
    begin
      if FileExists(InFile) then
        raise Exception.Create(S_INVALID_FILE)
      else
        raise Exception.Create(S_INVALID_PARAM);
    end;
  except
    on E: Exception do
    begin
      WriteLn(Format(S_ERR_S_S, [InFile, E.Message]));
      RequirePause := true;
    end;
  end;
end;

procedure ExpandAndProcess(const AArg: string; var RequirePause: boolean);
var
  DirPart, Pattern: string;
  Files: TArray<string>;
  FileName: string;
begin
  if (Pos('*', AArg) > 0) or (Pos('?', AArg) > 0) then
  begin
    DirPart := ExtractFilePath(AArg);
    Pattern := ExtractFileName(AArg);

    if DirPart = '' then
      DirPart := GetCurrentDir;

    Files := TDirectory.GetFiles(DirPart, Pattern, TSearchOption.soTopDirectoryOnly);

    for FileName in Files do
      ProcessFile(FileName, RequirePause);
  end
  else
  begin
    ProcessFile(ExpandFileName(AArg), RequirePause);
  end;
end;
{$ENDIF}

procedure Main;
{$IFDEF MSWINDOWS}
var
  i: integer;
  RequirePause: boolean;
begin
  if ParamCount < 1 then
  begin
    RequirePause := true;
    ShowUsage;
  end
  else
  begin
    RequirePause := false;
    for i := 1 to ParamCount do
    begin
      if ParamStr(i) = 'TEST' then
      begin
        try
          Testcases
        except
          on E: Exception do
          begin
            WriteLn(Format('Testcases Exception: %s', [e.Message]));
            RequirePause := true;
          end;
        end;
      end
      else
      ExpandAndProcess(ParamStr(i), RequirePause);
    end;
  end;

  if RequirePause then
  begin
    WriteLn(S_PRESS_ANY_KEY);
    ReadLn;
  end;
{$ELSE}
var
  InFile, OutFile, Ext: string;
begin
  if ParamCount < 1 then
  begin
    ShowUsage;
    Exit;
  end;

  InFile := ParamStr(1);
  if InFile = 'TEST' then
  begin
    Testcases;
    Exit;
  end;
  if ParamCount >= 2 then
    OutFile := ParamStr(2)
  else
  begin
    Ext := LowerCase(ExtractFileExt(InFile));
    if Ext = '.gxt' then
      OutFile := ChangeFileExt(InFile, '.txt')
    else if Ext = '.txt' then
      OutFile := ChangeFileExt(InFile, '.gxt')
    else
      raise Exception.Create(S_INVALID_FILE);
  end;

  Ext := LowerCase(ExtractFileExt(InFile));
  if Ext = '.gxt' then
    GxtToTxt(InFile, OutFile)
  else if Ext = '.txt' then
    TxtToGxt(InFile, OutFile)
  else
    raise Exception.Create(S_INVALID_FILE);
{$ENDIF}
end;

begin
  try
    Main;
  except
    on E: Exception do
    begin
      Writeln(Format(S_ERR_S_S, [E.ClassName, E.Message]));
      {$IFDEF FPC}
      Halt(1);
      {$ELSE}
      ExitCode := 1;
      {$ENDIF}
    end;
  end;
end.

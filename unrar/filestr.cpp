#include "rar.hpp"

static bool IsUnicode(byte *Data,int Size);

bool ReadTextFile(const char *Name,StringList *List,bool Config,bool AbortOnError,
                  RAR_CHARSET SrcCharset,bool Unquote,bool SkipComments)
{
  char FileName[NM];
  if (Config)
    GetConfigName(Name,FileName,true);
  else
    strcpy(FileName,Name);

  File SrcFile;
  if (*FileName)
  {
    bool OpenCode=AbortOnError ? SrcFile.WOpen(FileName):SrcFile.Open(FileName);

    if (!OpenCode)
    {
      if (AbortOnError)
        ErrHandler.Exit(OPEN_ERROR);
      return(false);
    }
  }
  else
    SrcFile.SetHandleType(FILE_HANDLESTD);

  unsigned int DataSize=0,ReadSize;
  const int ReadBlock=1024;
  Array<char> Data(ReadBlock+5);
  while ((ReadSize=SrcFile.Read(&Data[DataSize],ReadBlock))!=0)
  {
    DataSize+=ReadSize;
    Data.Add(ReadSize);
  }

  memset(&Data[DataSize],0,5);

  if (SrcCharset==RCH_UNICODE ||
      (SrcCharset==RCH_DEFAULT && IsUnicode((byte *)&Data[0],DataSize)))
  {
    // Unicode in native system format, can be more than 2 bytes per character
    Array<wchar> DataW(Data.Size()/2+1);
    for (int I=2;I<Data.Size()-1;I+=2)
      DataW[(I-2)/2]=(wchar)Data[I]+(wchar)Data[I+1]*256;

    wchar *CurStr=&DataW[0];
    Array<char> AnsiName;

    while (*CurStr!=0)
    {
      wchar *NextStr=CurStr,*CmtPtr=NULL;
      while (*NextStr!='\r' && *NextStr!='\n' && *NextStr!=0)
      {
        if (SkipComments && NextStr[0]=='/' && NextStr[1]=='/')
        {
          *NextStr=0;
          CmtPtr=NextStr;
        }
        NextStr++;
      }
      *NextStr=0;
      for (wchar *SpacePtr=(CmtPtr ? CmtPtr:NextStr)-1;SpacePtr>=CurStr;SpacePtr--)
      {
        if (*SpacePtr!=' ' && *SpacePtr!='\t')
          break;
        *SpacePtr=0;
      }
      if (*CurStr)
      {
        int Length=strlenw(CurStr);
        int AddSize=4*(Length-AnsiName.Size()+1);
        if (AddSize>0)
          AnsiName.Add(AddSize);
        if (Unquote && *CurStr=='\"' && CurStr[Length-1]=='\"')
        {
          CurStr[Length-1]=0;
          CurStr++;
        }
        WideToChar(CurStr,&AnsiName[0],AnsiName.Size());
        List->AddString(&AnsiName[0],CurStr);
      }
      CurStr=NextStr+1;
      while (*CurStr=='\r' || *CurStr=='\n')
        CurStr++;
    }
  }
  else
  {
    char *CurStr=&Data[0];
    while (*CurStr!=0)
    {
      char *NextStr=CurStr,*CmtPtr=NULL;
      while (*NextStr!='\r' && *NextStr!='\n' && *NextStr!=0)
      {
        if (SkipComments && NextStr[0]=='/' && NextStr[1]=='/')
        {
          *NextStr=0;
          CmtPtr=NextStr;
        }
        NextStr++;
      }
      *NextStr=0;
      for (char *SpacePtr=(CmtPtr ? CmtPtr:NextStr)-1;SpacePtr>=CurStr;SpacePtr--)
      {
        if (*SpacePtr!=' ' && *SpacePtr!='\t')
          break;
        *SpacePtr=0;
      }
      if (*CurStr)
      {
        if (Unquote && *CurStr=='\"')
        {
          int Length=strlen(CurStr);
          if (CurStr[Length-1]=='\"')
          {
            CurStr[Length-1]=0;
            CurStr++;
          }
        }
#if defined(_WIN_32)
        if (SrcCharset==RCH_OEM)
          OemToChar(CurStr,CurStr);
#endif
        List->AddString(CurStr);
      }
      CurStr=NextStr+1;
      while (*CurStr=='\r' || *CurStr=='\n')
        CurStr++;
    }
  }
  return(true);
}


bool IsUnicode(byte *Data,int Size)
{
  if (Size<4 || Data[0]!=0xff || Data[1]!=0xfe)
    return(false);
  for (int I=2;I<Size;I++)
    if (Data[I]<32 && Data[I]!='\r' && Data[I]!='\n')
      return(true);
  return(false);
}

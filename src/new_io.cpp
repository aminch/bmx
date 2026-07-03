#include <_ansi.h>
#include <_syslist.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#undef errno
extern int errno;

#include "circle_glue.h"
#include <assert.h>

#include <malloc.h>
#include <sys/unistd.h>
#include <circle/serial.h>
#include <circle/timer.h>

#include <ff.h>

// This is a replacement io.cpp specifically for BMC64.
// This implementation will sometimes load the entire file
// into memory to provide faster seek operations, improving
// performance on slow SD cards.  Since any file the emulator
// attempts to load is relatively small (<200k), this works out
// just fine for our needs. Obviously, this would not be a
// viable solution for most other circumstances.  It also
// works around an issue with circle/fatfs integration that
// was causing memory corruption.
//
// When a file is opened for READ ONLY, fatfs is used to open
// the file.  As long as the client never seeks, the file will
// not be loaded into ram and the disk still backs the data.  As
// soon as seek is called, the file will be loaded into ram and
// from then on, ram backs the data.  NOTE the fatfs file remains
// open even after the file is loaded into ram in this case. If
// the client never calls seek, the data will be read from fatfs.
//
// When a file is opened for WRITE ONLY, fatfs is used to create
// the file. However, all write operations write to ram and only
// when the file is finally closed will the data be dumped to
// the fat fs filesystem.  The fatfs file remains open during
// the entire time between open/close.  Seek is technically
// supported in this case but attempting to seek past the
// current file size is not.  Call to fstat on a file in WRTE_ONLY
// mode will not work as expected.
//
// When a file is opened for READ_WRITE, fat fs is used to
// immediately load the contents of the existing file into ram.
// The input fat fs file is immediatly closed in this case.
// Writes & seeks use the ram copy. Only when the file is closed
// will the fatfs system be used to create a new file from the ram.
// Again, seeking past the file's current length is not supported.

#define MAX_OPEN_FILES 10
#define MAX_OPEN_DIRS 10
#define READ_BUF_SIZE 1024
#define BMC64_PATH_MAX 256

static const char *pattern = "*";

static char currentDir[BMC64_PATH_MAX];

static bool copy_string(char *dst, size_t dst_size, const char *src) {
  if (dst_size == 0) {
    return false;
  }
  if (src == nullptr) {
    dst[0] = '\0';
    return true;
  }

  size_t len = strlen(src);
  if (len >= dst_size) {
    dst[0] = '\0';
    return false;
  }

  memcpy(dst, src, len + 1);
  return true;
}

static bool append_string(char *dst, size_t dst_size, const char *src) {
  size_t used = strlen(dst);
  size_t len = strlen(src);
  if (used >= dst_size || len >= dst_size - used) {
    return false;
  }

  memcpy(dst + used, src, len + 1);
  return true;
}

static bool has_fatfs_volume_prefix(const char *path) {
  const char *colon = strchr(path, ':');
  if (colon == nullptr) {
    return false;
  }

  const char *slash = strchr(path, '/');
  return slash == nullptr || colon < slash;
}

static bool is_absolute_path(const char *path) {
  return path[0] == '/' || has_fatfs_volume_prefix(path);
}

static bool is_root_path(const char *path) {
  if (strcmp(path, "/") == 0) {
    return true;
  }

  const char *colon = strchr(path, ':');
  return colon != nullptr &&
         (colon[1] == '\0' || (colon[1] == '/' && colon[2] == '\0'));
}

static void strip_trailing_slash(char *path) {
  size_t len = strlen(path);
  while (len > 1 && path[len - 1] == '/' && !is_root_path(path)) {
    path[--len] = '\0';
  }
}

static bool append_path_component(char *path, size_t path_size,
                                  const char *component) {
  if (component[0] == '\0') {
    return true;
  }

  size_t len = strlen(path);
  if (len > 0 && path[len - 1] != '/') {
    if (!append_string(path, path_size, "/")) {
      return false;
    }
  }

  return append_string(path, path_size, component);
}

static void move_current_dir_to_parent() {
  strip_trailing_slash(currentDir);
  if (is_root_path(currentDir)) {
    return;
  }

  char *last_slash = strrchr(currentDir, '/');
  if (last_slash == nullptr) {
    copy_string(currentDir, sizeof currentDir, "/");
    return;
  }

  if (last_slash == currentDir) {
    currentDir[1] = '\0';
    return;
  }

  const char *colon = strchr(currentDir, ':');
  if (colon != nullptr && last_slash == colon + 1) {
    last_slash[1] = '\0';
    return;
  }

  *last_slash = '\0';
}

/**
 * @fn int strend(const char *s, const char *t)
 * @brief Searches the end of string s for string t
 * @param s the string to be searched
 * @param t the substring to locate at the end of string s
 * @return one if the string t occurs at the end of the string s, and zero otherwise
 */
int strend(const char *s, const char *t)
{
    size_t ls = strlen(s); // find length of s
    size_t lt = strlen(t); // find length of t
    if (ls >= lt)  // check if t can fit in s
    {
        // point s to where t should start and compare the strings from there
        return (0 == memcmp(t, s + (ls - lt), lt));
    }
    return 0; // t was longer than s
}

static void reverse(char *x, int begin, int end) {
  char c;

  if (begin >= end)
    return;

  c = *(x + begin);
  *(x + begin) = *(x + end);
  *(x + end) = c;

  reverse(x, ++begin, --end);
}

static void itoa2(int i, char *dst) {
  int q = 0;
  int j;
  do {
    j = i % 10;
    dst[q] = '0' + j;
    q++;
    i = i / 10;
  } while (i > 0);
  dst[q] = '\0';

  reverse(dst, 0, strlen(dst) - 1);
}

CSerialDevice *g_serial;

static int SerialWriteAll(const char *ptr, int len) {
   if (!g_serial) {
      return len;
   }

   int written = 0;
   unsigned idle_loops = 0;
   while (written < len) {
      int result = g_serial->Write(ptr + written, len - written);
      if (result > 0) {
         written += result;
         idle_loops = 0;
         continue;
      }

      if (++idle_loops > 200000) {
         break;
      }
      CTimer::SimpleusDelay(1);
   }

   unsigned drain_loops = 0;
   while (written > 0 && g_serial->IsTransmitting()) {
      if (++drain_loops > 2000000) {
         break;
      }
      CTimer::SimpleusDelay(1);
   }

   return written;
}

static void logm(const char *msg) {
   if (g_serial) {
      SerialWriteAll(msg, strlen(msg));
   }
}

static void logi(int i) {
   char nn[16];
   itoa2(i,nn);
   if (g_serial) {
      SerialWriteAll(nn, strlen(nn));
   }
}

struct CirclePath {
   CirclePath(const char* p) {
      ok = false;
      error = 0;
      path[0] = '\0';

      if (p == nullptr) {
         error = EFAULT;
         return;
      }

      size_t len = strlen(p);
      if (len == 0) {
         ok = true;
         return;
      }

      if (is_absolute_path(p)) {
         // Absolute
         if (!copy_string(path, sizeof path, p)) {
            error = ENAMETOOLONG;
            return;
         }
         strip_trailing_slash(path);
         ok = true;
         return;
      } 

      // Relative
      if (!copy_string(path, sizeof path, currentDir)) {
         error = ENAMETOOLONG;
         return;
      }
      if (len == 1 && p[0] == '.') {
         // Treat as current dir
         strip_trailing_slash(path);
         ok = true;
         return;
      }

      // Handle ./ at start but we don't in the middle.
      const char *relative = p;
      if (len >= 2 && p[0] == '.' && p[1] == '/') {
         relative = p + 2;
      }

      if (!append_path_component(path, sizeof path, relative)) {
         error = ENAMETOOLONG;
         return;
      }

      // Fat fs doesn't like trailing slashes for dirs
      strip_trailing_slash(path);
      ok = true;
   }

   bool ok;
   int error;
   char path[BMC64_PATH_MAX];
};

struct CircleFile {
  FIL file;
  int in_use;
  char fname[BMC64_PATH_MAX];

  char readBuf[READ_BUF_SIZE]; // tmp read buffer
  char *contents; // bytes for file in memory
  unsigned allocated; // total bytes allocated for in memory file
  unsigned size; // total size of file in memory file
  unsigned position; // current in memory write position
  int mode; // remembers mode this file was opened under
  int written_to; // at least one write was performed on this file
  int fopen_called; // f_open was called and thus f_close needs to be called
};

struct CircleDir {
  CircleDir() {
    mEntry.d_ino = 0;
    mEntry.d_name[0] = 0;
    dir.pat = pattern;
    in_use = 0;
  }

  FATFS_DIR dir;
  int in_use;
  struct dirent mEntry;
};

CircleFile fileTab[MAX_OPEN_FILES];
CircleDir dirTab[MAX_OPEN_DIRS];

void CGlueStdioInit(CSerialDevice *serial) {
  g_serial = serial;
  setvbuf(stdout, nullptr, _IONBF, 0);
  setvbuf(stderr, nullptr, _IONBF, 0);

  // Initialize stdio, stderr and stdin
  fileTab[0].in_use = 1;
  fileTab[1].in_use = 1;
  fileTab[2].in_use = 1;

  copy_string(currentDir, sizeof currentDir, "/");
}

static int g_bootStatNum = 0;
static int *g_bootStatWhat;
static const char **g_bootStatFile;
static int *g_bootStatSize;

// Set global vars pointing to bootstat info
void CGlueStdioInitBootStat (int num,
        int *bootStatWhat,
        const char **bootStatFile,
        int *bootStatSize) {
   g_bootStatNum = num;
   g_bootStatWhat = bootStatWhat;
   g_bootStatFile = bootStatFile;
   g_bootStatSize = bootStatSize;
}

static int FindFreeFileSlot(void) {
  int slotNr = -1;

  for (const CircleFile &slot : fileTab) {
    if (slot.in_use == 0) {
      slotNr = &slot - fileTab;
      break;
    }
  }

  return slotNr;
}

static char *strdup2(const char *s) {
  char *d = (char *)malloc(strlen(s) + 1);
  if (d == nullptr)
    return nullptr;
  strcpy(d, s);
  return d;
}

static int ensure_file_capacity(CircleFile &file, unsigned required) {
  if (required <= file.allocated) {
    return 0;
  }

  unsigned new_allocated = file.allocated ? file.allocated : READ_BUF_SIZE;
  while (new_allocated < required) {
    if (new_allocated > UINT_MAX / 2) {
      errno = ENOMEM;
      return -1;
    }
    new_allocated *= 2;
  }

  char *new_contents;
  if (file.contents == nullptr) {
    new_contents = (char *)malloc(new_allocated);
  } else {
    new_contents = (char *)realloc(file.contents, new_allocated);
  }

  if (new_contents == nullptr) {
    errno = ENOMEM;
    return -1;
  }

  file.contents = new_contents;
  file.allocated = new_allocated;
  return 0;
}

static void discard_file_contents(CircleFile &file) {
  if (file.contents != nullptr) {
    free(file.contents);
    file.contents = nullptr;
  }
  file.allocated = 0;
  file.size = 0;
  file.position = 0;
}


static int FindFreeDirSlot(void) {
  int slotNr = -1;

  for (const CircleDir &slot : dirTab) {
    if (!slot.in_use) {
      slotNr = &slot - dirTab;
      break;
    }
  }

  return slotNr;
}

static CircleDir *FindCircleDirFromDIR(DIR *dir) {
  for (CircleDir &slot : dirTab) {
    if (slot.in_use && dir == reinterpret_cast<DIR *>(&slot.dir)) {
      return &slot;
    }
  }
  return nullptr;
}

// Returns non zero value on any failure. Any memory will be
// freed on error and file.contents nulled.
static int slurp_file(CircleFile &file) {
  if (file.contents == nullptr) {
    // Read the entire contents of the file into memory.
    file.size = 0;
    unsigned total = 0;
    if (f_lseek(&file.file, 0) != FR_OK) {
       errno = EIO;
       return -1;
    }
    while (true) {
      unsigned int num_read;
      if (f_read(&file.file, file.readBuf, READ_BUF_SIZE, &num_read) != FR_OK) {
        discard_file_contents(file);
        errno = EIO;
        return -1;
      }

      if (num_read == 0) {
        break;
      }

      if (num_read > UINT_MAX - total) {
        discard_file_contents(file);
        errno = ENOMEM;
        return -1;
      }

      if (ensure_file_capacity(file, total + num_read) != 0) {
        discard_file_contents(file);
        return -1;
      }

      memcpy(file.contents + total, file.readBuf, num_read);
      total += num_read;
      file.size = total;
    }
  }
  return 0;
}

extern "C" int _open(char *file, int flags, int mode) {
  (void) mode;
  if (file == nullptr) {
    errno = EFAULT;
    return -1;
  }

  int const masked_flags = flags & 7;
  if (masked_flags != O_RDONLY && masked_flags != O_WRONLY &&
      masked_flags != O_RDWR) {
    errno = ENOSYS;
    return -1;
  }

  // Handle fast fail here
  for (int i=0;i<g_bootStatNum;i++) {
     if (g_bootStatWhat[i] == BOOTSTAT_WHAT_FAIL) {
        if (strend(file, g_bootStatFile[i])) {
          errno = EACCES;
          return -1;
        }
     }
  }
  int slot = FindFreeFileSlot();

  if (slot != -1) {
    CirclePath circlePath(file);
    if (!circlePath.ok) {
      errno = circlePath.error;
      return -1;
    }

    CircleFile &newFile = fileTab[slot];
    newFile.fopen_called = 0;
    newFile.contents = nullptr;
    newFile.position = 0;
    newFile.size = 0;
    newFile.allocated = 0;
    newFile.mode = masked_flags;
    newFile.written_to = 0;
    newFile.fname[0] = '\0';

    int result;
    if (masked_flags == O_RDONLY) {
      result = f_open(&newFile.file, circlePath.path, FA_READ);
    } else if (masked_flags == O_WRONLY) {
      result = f_open(&newFile.file, circlePath.path, 
         FA_WRITE | FA_CREATE_ALWAYS);
    } else {
      assert(masked_flags == O_RDWR);
      // Note: We open read only because this will be slurped and changed
      // in memory.
      result = f_open(&newFile.file, circlePath.path, FA_READ);
    }

    if (result != FR_OK) {
      errno = EACCES;
      return -1;
    }

    newFile.fopen_called = 1;
    if (!copy_string(newFile.fname, sizeof newFile.fname, circlePath.path)) {
      f_close(&newFile.file);
      errno = ENAMETOOLONG;
      return -1;
    }

    // When file is opened O_RDWR, slurp it into memory.
    if (masked_flags == O_RDWR) {
       if (slurp_file(newFile)) {
          f_close(&newFile.file);
          discard_file_contents(newFile);
          newFile.fopen_called = 0;
          if (errno == 0) {
            errno = ENFILE;
          }
          return -1;
       }
       if (f_close(&newFile.file) != FR_OK) {
          discard_file_contents(newFile);
          newFile.fopen_called = 0;
          errno = ENFILE;
          return -1;
       }
       newFile.fopen_called = 0;
    }

    newFile.in_use = 1;
  } else {
    errno = ENFILE;
  }

  return slot;
}

extern "C" int _close(int fildes) {
  if (fildes < 0 || static_cast<unsigned int>(fildes) >= MAX_OPEN_FILES) {
    errno = EBADF;
    return -1;
  }

  CircleFile &file = fileTab[fildes];
  if (!file.in_use) {
    errno = EBADF;
    return -1;
  }

  int flush_error = 0;
  if (file.contents) {
     // Only open if something was actually written to memory
     if (file.mode == O_RDWR && file.written_to) {
        // Assert FIL is not used
        file.fopen_called = 1;
        if (f_open(&file.file, file.fname,
                      FA_WRITE | FA_CREATE_ALWAYS) != FR_OK) {
           // We won't be able to flush in memory changes back to disk.
           file.fopen_called = 0;
           flush_error = 1;
        }
     }

     // Always flush to disk for WRONLY but only if written to for RDRW
     if (!flush_error &&
         ((file.mode == O_RDWR && file.written_to) || file.mode == O_WRONLY)) {
        // Dump contents of memory buffer to actual file.
        unsigned int num_written;
        if (f_write(&file.file, file.contents,
                      file.size, &num_written) != FR_OK ||
             num_written != file.size) {
           // Can't write new file or modified file contents back to disk.
           flush_error = 1;
        }
     }
  }

  int need_close = file.fopen_called;

  file.allocated = 0;
  file.size = 0;
  file.mode = 0;
  file.in_use = 0;
  file.written_to = 0;
  file.fopen_called = 0;
  file.fname[0] = '\0';

  if (file.contents) {
    free(file.contents);
    file.contents = nullptr;
  } 
  
  // If we opened for RDWR but never wrote, nothing do to.
  if (need_close && f_close(&file.file) != FR_OK) {
    flush_error = 1;
  }

  if (flush_error) {
    errno = EIO;
    return -1;
  }

  return 0;
}

extern "C" int _read(int fildes, char *ptr, int len) {
  if (fildes < 0 || static_cast<unsigned int>(fildes) >= MAX_OPEN_FILES) {
    errno = EBADF;
    return -1;
  }
  if (len < 0) {
    errno = EINVAL;
    return -1;
  }
  if (len > 0 && ptr == nullptr) {
    errno = EFAULT;
    return -1;
  }

  CircleFile &file = fileTab[fildes];
  if (!file.in_use) {
    errno = EBADF;
    return -1;
  }

  unsigned int num_read;
  if (file.contents == nullptr) {
     // Assert file.FIL has been opened
     // else EBADF -1

     // Read data from the file
     if (f_read(&file.file, ptr, len, &num_read) != FR_OK) {
       errno = EIO;
       return -1;
     }

     file.position += num_read;
     return static_cast<int>(num_read);
  } else {
     // Read data from our internal buffer
     unsigned int max = len;
     unsigned int remain = file.position <= file.size ?
                           file.size - file.position : 0;

     if (max > remain) {
        max = remain;
     }

     if (max > 0) {
        memcpy(ptr, file.contents + file.position, max);
        file.position += max;
     }
     return static_cast<int>(max);
  }
}

extern "C" int _write(int fildes, char *ptr, int len) {
  if (fildes < 0 || static_cast<unsigned int>(fildes) >= MAX_OPEN_FILES) {
    errno = EBADF;
    return -1;
  }
  if (len < 0) {
    errno = EINVAL;
    return -1;
  }
  if (len > 0 && ptr == nullptr) {
    errno = EFAULT;
    return -1;
  }

  if (fildes == 1 || fildes == 2) {
    if (g_serial) {
       return SerialWriteAll(ptr, len);
    } 
    return len;
  }

  CircleFile &file = fileTab[fildes];
  if (!file.in_use) {
    errno = EBADF;
    return -1;
  }

  // Mark this dirty so it will be flushed from memory to disk on close
  file.written_to = 1;

  // Nothing allocated yet? Allocate now.
  if ((unsigned)len > UINT_MAX - file.position) {
     errno = ENOMEM;
     return -1;
  }
  unsigned required = file.position + (unsigned)len;
  if (ensure_file_capacity(file, required) != 0) {
     return -1;
  }

  // Do the write.
  if (len > 0) {
    memcpy(file.contents + file.position, ptr, len);
  }
  file.position += len;
  if (file.position > file.size) {
     file.size = file.position;
  }

  return len;
}

extern "C" DIR *opendir(const char *name) {
  CirclePath circlePath(name); 
  if (!circlePath.ok) {
    errno = circlePath.error;
    return 0;
  }
  
  int const slotNum = FindFreeDirSlot();
  if (slotNum == -1) {
    errno = ENFILE;
    return 0;
  }

  CircleDir &slot = dirTab[slotNum];
  if (f_opendir(&slot.dir, circlePath.path) != FR_OK) {
    errno = ENFILE;
    return 0;
  }

  slot.in_use = 1;
  return reinterpret_cast<DIR *>(&slot.dir);
}

static struct dirent *do_readdir(CircleDir *dir, struct dirent *de) {

  assert(dir->in_use);

  FILINFO fno;
  struct dirent *result = nullptr;

  FRESULT res = f_findnext(&dir->dir, &fno);
  if (res == FR_OK && fno.fname[0] != 0) {
    snprintf(de->d_name, sizeof de->d_name, "%s", fno.fname);
    de->d_ino = 0;
    result = de;
  }

  return result;
}

extern "C" struct dirent *readdir(DIR *dir) {
  CircleDir *c_dir = FindCircleDirFromDIR(dir);
  if (c_dir == nullptr) {
    errno = EBADF;
    return nullptr;
  }

  return do_readdir(c_dir, &c_dir->mEntry);
}

extern "C" int readdir_r(DIR *__restrict dir, dirent *__restrict de,
                         dirent **__restrict ode) {
  int result;
  CircleDir *c_dir = FindCircleDirFromDIR(dir);

  if (c_dir == nullptr) {
    *ode = nullptr;
    result = EBADF;
  } else {
    *ode = do_readdir(c_dir, de);
    result = 0;
  }

  return result;
}

extern "C" void rewinddir(DIR *dir) {
  CircleDir *c_dir = FindCircleDirFromDIR(dir);
  if (c_dir != nullptr) {
    f_rewinddir(&c_dir->dir);
  }
}

extern "C" int closedir(DIR *dir) {
  CircleDir *c_dir = FindCircleDirFromDIR(dir);
  if (c_dir == nullptr) {
    errno = EBADF;
    return -1;
  }

  c_dir->in_use = 0;

  if (f_closedir(&c_dir->dir) != FR_OK) {
    errno = EIO;
    return -1;
  }

  return 0;
}

extern "C" int _stat(const char *file, struct stat *st) {
  if (st == nullptr) {
    errno = EFAULT;
    return -1;
  }

  CirclePath circlePath(file);
  if (!circlePath.ok) {
    errno = circlePath.error;
    return -1;
  }

  memset(st, 0, sizeof(struct stat));

  // Fastfail or fastsucceed
  for (int i=0;i<g_bootStatNum;i++) {
     if (g_bootStatWhat[i] == BOOTSTAT_WHAT_STAT) {
        if (strend(circlePath.path, g_bootStatFile[i])) {
           st->st_mode = S_IFREG | S_IREAD | S_IWRITE;
           st->st_size = g_bootStatSize[i];
           return 0;
        }
     }
     else if (g_bootStatWhat[i] == BOOTSTAT_WHAT_FAIL) {
        if (strend(circlePath.path, g_bootStatFile[i])) {
          errno = EBADF;
          return -1;
        }
     }
  }

  FILINFO fno;
  if (f_stat(circlePath.path, &fno) == FR_OK) {
    if (fno.fattrib & AM_DIR) {
      st->st_mode |= S_IFDIR;
    } else {
      st->st_mode |= S_IFREG;
    }
    if (fno.fattrib & AM_RDO) {
      st->st_mode |= S_IREAD;
    } else {
      st->st_mode |= S_IREAD | S_IWRITE;
    }

    st->st_size = fno.fsize;
    return 0;
  }

  errno = EBADF;
  return -1;
}

extern "C" int access(const char *path, int mode) {
  if (path == nullptr) {
    errno = EFAULT;
    return -1;
  }

  CirclePath circlePath(path);
  if (!circlePath.ok) {
    errno = circlePath.error;
    return -1;
  }

  FILINFO fno;
  if (f_stat(circlePath.path, &fno) != FR_OK) {
    errno = ENOENT;
    return -1;
  }

  if (mode & X_OK) {
    errno = EACCES;
    return -1;
  }

  return 0;
}

extern "C" int _access(const char *path, int mode) {
  return access(path, mode);
}

extern "C" int _fstat(int fildes, struct stat *st) {
  if (st == nullptr) {
    errno = EFAULT;
    return -1;
  }
  if (fildes < 0 || static_cast<unsigned int>(fildes) >= MAX_OPEN_FILES) {
    errno = EBADF;
    return -1;
  }

  CircleFile &file = fileTab[fildes];
  if (!file.in_use) {
    errno = EBADF;
    return -1;
  }

  return _stat(file.fname, st);
}

extern "C" int _lseek(int fildes, int ptr, int dir) {

  if (fildes < 0 || static_cast<unsigned int>(fildes) >= MAX_OPEN_FILES) {
    errno = EBADF;
    return -1;
  }

  CircleFile &file = fileTab[fildes];
  if (!file.in_use) {
    errno = EBADF;
    return -1;
  }

  if (file.mode == O_RDONLY) {
    // Assert FIL has been opened
    if (slurp_file(file)) {
       if (errno == 0) {
          errno = EACCES;
       }
       return -1;
    }
  }

  long long next_position;
  if (dir == SEEK_SET) {
    next_position = ptr;
  } else if (dir == SEEK_CUR) {
    next_position = (long long)file.position + ptr;
  } else if (dir == SEEK_END) {
    next_position = (long long)file.size + ptr;
  } else {
    errno = EINVAL;
    return -1;
  }

  if (next_position < 0 || next_position > (long long)file.size) {
    errno = EINVAL;
    return -1;
  }

  file.position = (unsigned)next_position;
  return file.position;
}

int chdir (const char *path)
{
  if (path == nullptr) {
     errno = EIO;
     return -1;
  }

  size_t len = strlen(path);
  if (len == 0) {
     return 0;
  }

  if (len == 1 && path[0] == '.') {
     return 0;
  }

  // Up to parent
  if (len == 2 && path[0] == '.' && path[1] == '.') {
     move_current_dir_to_parent();
     return 0;
  }

  CirclePath circlePath(path);
  if (!circlePath.ok) {
     errno = circlePath.error;
     return -1;
  }
  if (!copy_string(currentDir, sizeof currentDir, circlePath.path)) {
     errno = ENAMETOOLONG;
     return -1;
  }

  return 0;
}

char *getwd(char *buf) {
   if (buf) {
      if (!copy_string(buf, BMC64_PATH_MAX, currentDir)) {
         errno = ENAMETOOLONG;
         return nullptr;
      }
      strip_trailing_slash(buf);
   }
   return buf;
}

extern "C" int _link(char *existing, char *newname) {
  CirclePath existingPath(existing);
  CirclePath newPath(newname);
  if (!existingPath.ok) {
     errno = existingPath.error;
     return -1;
  }
  if (!newPath.ok) {
     errno = newPath.error;
     return -1;
  }

  int result = f_rename(existingPath.path, newPath.path);
  if (result != FR_OK) {
     if (result == FR_EXIST) errno = EEXIST;
     else errno = EBADF;
     return -1;
  }
  return 0;
}

extern "C" int _unlink(char *name) {
  CirclePath circlePath(name);
  if (!circlePath.ok) {
     errno = circlePath.error;
     return -1;
  }

  if (f_unlink(circlePath.path) != FR_OK) {
     errno = EBADF;
     return -1;
  }
  return 0;
}

extern "C" int _isatty(int fildes) {
  return fildes >= 0 && fildes <= 2 ? 1 : 0;
}

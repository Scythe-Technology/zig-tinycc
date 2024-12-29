#ifndef RELOCATE_H
#define RELOCATE_H

#ifndef LIBTCCAPI
# define LIBTCCAPI
#endif

/* do all relocations (needed before using tcc_get_symbol()) */
// mode
// 0: auto
// 1: use provided ptr as buffer
// 2: only calculate size
LIBTCCAPI int tcc_relocate2(TCCState *s1, void *ptr, int mode);

#endif
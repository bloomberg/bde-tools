#include <other.h>

void f1_1_F();
void f1_2_F(int);

template <class T> void f1_1_T();
template <class T> void f1_2_T(int);

template <class T, template <class> class U> void f1_1_U(U<T>);
template <class T, template <class> class U> void f1_2_U(U<T>, int);

struct DefHF { struct ID { }; struct IC; };
struct DecHF;

typedef DefHF DefYHF;
typedef DecHF DecYHF;

template <class T> struct DefHTF { struct ID { }; struct IC; };
template <class T> struct DecHTF;

namespace
{
struct DefHAN { struct ID { }; struct IC; };
struct DecHAN;

typedef DefHF DefYHF;
typedef DecHF DecYHF;

template <class T> struct DefHTAN { struct ID { }; struct IC; };
template <class T> struct DecHTAN;
}

namespace N
{
struct DefHN { struct ID { }; struct IC; };
struct DecHN;

typedef DefHF DefYHF;
typedef DecHF DecYHF;

template <class T> struct DefHTN { struct ID { }; struct IC; };
template <class T> struct DecHTN;
}

void f1_1_DecHF(DecHF);
void f1_2_DecHF(const DecHF *);
void f1_3_DecHF(volatile DecHF &);
void f1_4_DecHF(int, DecHF);
void f1_5_DecHF(int, const DecHF *);
void f1_6_DecHF(int, volatile DecHF &);
void f1_1_DefHF(DefHF);
void f1_2_DefHF(const DefHF *);
void f1_3_DefHF(volatile DefHF &);
void f1_4_DefHF(int, DefHF);
void f1_5_DefHF(int, const DefHF *);
void f1_6_DefHF(int, volatile DefHF &);
void f1_1_DefHFId(DefHF::ID);
void f1_2_DefHFId(const DefHF::ID *);
void f1_3_DefHFId(volatile DefHF::ID &);
void f1_4_DefHFId(int, DefHF::ID);
void f1_5_DefHFId(int, const DefHF::ID *);
void f1_6_DefHFId(int, volatile DefHF::ID &);
void f1_1_DefHFIf(DefHF::IC);
void f1_2_DefHFIf(const DefHF::IC *);
void f1_3_DefHFIf(volatile DefHF::IC &);
void f1_4_DefHFIf(int, DefHF::IC);
void f1_5_DefHFIf(int, const DefHF::IC *);
void f1_6_DefHFIf(int, volatile DefHF::IC &);
void f1_1_DecOHF(DecOHF);
void f1_2_DecOHF(const DecOHF *);
void f1_3_DecOHF(volatile DecOHF &);
void f1_4_DecOHF(int, DecOHF);
void f1_5_DecOHF(int, const DecOHF *);
void f1_6_DecOHF(int, volatile DecOHF &);
void f1_1_DefOHF(DefOHF);
void f1_2_DefOHF(const DefOHF *);
void f1_3_DefOHF(volatile DefOHF &);
void f1_4_DefOHF(int, DefOHF);
void f1_5_DefOHF(int, const DefOHF *);
void f1_6_DefOHF(int, volatile DefOHF &);
void f1_1_DefOHFId(DefOHF::ID);
void f1_2_DefOHFId(const DefOHF::ID *);
void f1_3_DefOHFId(volatile DefOHF::ID &);
void f1_4_DefOHFId(int, DefOHF::ID);
void f1_5_DefOHFId(int, const DefOHF::ID *);
void f1_6_DefOHFId(int, volatile DefOHF::ID &);
void f1_1_DefOHFIf(DefOHF::IC);
void f1_2_DefOHFIf(const DefOHF::IC *);
void f1_3_DefOHFIf(volatile DefOHF::IC &);
void f1_4_DefOHFIf(int, DefOHF::IC);
void f1_5_DefOHFIf(int, const DefOHF::IC *);
void f1_6_DefOHFIf(int, volatile DefOHF::IC &);
void f1_1_DecHAN(DecHAN);
void f1_2_DecHAN(const DecHAN *);
void f1_3_DecHAN(volatile DecHAN &);
void f1_4_DecHAN(int, DecHAN);
void f1_5_DecHAN(int, const DecHAN *);
void f1_6_DecHAN(int, volatile DecHAN &);
void f1_1_DefHAN(DefHAN);
void f1_2_DefHAN(const DefHAN *);
void f1_3_DefHAN(volatile DefHAN &);
void f1_4_DefHAN(int, DefHAN);
void f1_5_DefHAN(int, const DefHAN *);
void f1_6_DefHAN(int, volatile DefHAN &);
void f1_1_DefHANId(DefHAN::ID);
void f1_2_DefHANId(const DefHAN::ID *);
void f1_3_DefHANId(volatile DefHAN::ID &);
void f1_4_DefHANId(int, DefHAN::ID);
void f1_5_DefHANId(int, const DefHAN::ID *);
void f1_6_DefHANId(int, volatile DefHAN::ID &);
void f1_1_DefHANIf(DefHAN::IC);
void f1_2_DefHANIf(const DefHAN::IC *);
void f1_3_DefHANIf(volatile DefHAN::IC &);
void f1_4_DefHANIf(int, DefHAN::IC);
void f1_5_DefHANIf(int, const DefHAN::IC *);
void f1_6_DefHANIf(int, volatile DefHAN::IC &);
void f1_1_DecOHAN(DecOHAN);
void f1_2_DecOHAN(const DecOHAN *);
void f1_3_DecOHAN(volatile DecOHAN &);
void f1_4_DecOHAN(int, DecOHAN);
void f1_5_DecOHAN(int, const DecOHAN *);
void f1_6_DecOHAN(int, volatile DecOHAN &);
void f1_1_DefOHAN(DefOHAN);
void f1_2_DefOHAN(const DefOHAN *);
void f1_3_DefOHAN(volatile DefOHAN &);
void f1_4_DefOHAN(int, DefOHAN);
void f1_5_DefOHAN(int, const DefOHAN *);
void f1_6_DefOHAN(int, volatile DefOHAN &);
void f1_1_DefOHANId(DefOHAN::ID);
void f1_2_DefOHANId(const DefOHAN::ID *);
void f1_3_DefOHANId(volatile DefOHAN::ID &);
void f1_4_DefOHANId(int, DefOHAN::ID);
void f1_5_DefOHANId(int, const DefOHAN::ID *);
void f1_6_DefOHANId(int, volatile DefOHAN::ID &);
void f1_1_DefOHANIf(DefOHAN::IC);
void f1_2_DefOHANIf(const DefOHAN::IC *);
void f1_3_DefOHANIf(volatile DefOHAN::IC &);
void f1_4_DefOHANIf(int, DefOHAN::IC);
void f1_5_DefOHANIf(int, const DefOHAN::IC *);
void f1_6_DefOHANIf(int, volatile DefOHAN::IC &);
void f1_1_DefYHF(DefYHF);
void f1_2_DefYHF(const DefYHF *);
void f1_3_DefYHF(volatile DefYHF &);
void f1_4_DefYHF(int, DefYHF);
void f1_5_DefYHF(int, const DefYHF *);
void f1_6_DefYHF(int, volatile DefYHF &);
void f1_1_DecYHF(DecYHF);
void f1_2_DecYHF(const DecYHF *);
void f1_3_DecYHF(volatile DecYHF &);
void f1_4_DecYHF(int, DecYHF);
void f1_5_DecYHF(int, const DecYHF *);
void f1_6_DecYHF(int, volatile DecYHF &);
template <class T>
void f1_1_DecHTF(DecHTF<T>);
template <class T>
void f1_2_DecHTF(const DecHTF<T> *);
template <class T>
void f1_3_DecHTF(volatile DecHTF<T> &);
template <class T>
void f1_4_DecHTF(int, DecHTF<T>);
template <class T>
void f1_5_DecHTF(int, const DecHTF<T> *);
template <class T>
void f1_6_DecHTF(int, volatile DecHTF<T> &);
template <class T>
void f1_1_DefHTF(DefHTF<T>);
template <class T>
void f1_2_DefHTF(const DefHTF<T> *);
template <class T>
void f1_3_DefHTF(volatile DefHTF<T> &);
template <class T>
void f1_4_DefHTF(int, DefHTF<T>);
template <class T>
void f1_5_DefHTF(int, const DefHTF<T> *);
template <class T>
void f1_6_DefHTF(int, volatile DefHTF<T> &);
template <class T>
void f1_1_DefHTFId(typename DefHTF<T>::ID);
template <class T>
void f1_2_DefHTFId(const typename DefHTF<T>::ID *);
template <class T>
void f1_3_DefHTFId(volatile typename DefHTF<T>::ID &);
template <class T>
void f1_4_DefHTFId(int, typename DefHTF<T>::ID);
template <class T>
void f1_5_DefHTFId(int, const typename DefHTF<T>::ID *);
template <class T>
void f1_6_DefHTFId(int, volatile typename DefHTF<T>::ID &);
template <class T>
void f1_1_DefHTFIf(typename DefHTF<T>::IC);
template <class T>
void f1_2_DefHTFIf(const typename DefHTF<T>::IC *);
template <class T>
void f1_3_DefHTFIf(volatile typename DefHTF<T>::IC &);
template <class T>
void f1_4_DefHTFIf(int, typename DefHTF<T>::IC);
template <class T>
void f1_5_DefHTFIf(int, const typename DefHTF<T>::IC *);
template <class T>
void f1_6_DefHTFIf(int, volatile typename DefHTF<T>::IC &);
template <class T>
void f1_1_DecOHTF(DecOHTF<T>);
template <class T>
void f1_2_DecOHTF(const DecOHTF<T> *);
template <class T>
void f1_3_DecOHTF(volatile DecOHTF<T> &);
template <class T>
void f1_4_DecOHTF(int, DecOHTF<T>);
template <class T>
void f1_5_DecOHTF(int, const DecOHTF<T> *);
template <class T>
void f1_6_DecOHTF(int, volatile DecOHTF<T> &);
template <class T>
void f1_1_DefOHTF(DefOHTF<T>);
template <class T>
void f1_2_DefOHTF(const DefOHTF<T> *);
template <class T>
void f1_3_DefOHTF(volatile DefOHTF<T> &);
template <class T>
void f1_4_DefOHTF(int, DefOHTF<T>);
template <class T>
void f1_5_DefOHTF(int, const DefOHTF<T> *);
template <class T>
void f1_6_DefOHTF(int, volatile DefOHTF<T> &);
template <class T>
void f1_1_DefOHTFId(typename DefOHTF<T>::ID);
template <class T>
void f1_2_DefOHTFId(const typename DefOHTF<T>::ID *);
template <class T>
void f1_3_DefOHTFId(volatile typename DefOHTF<T>::ID &);
template <class T>
void f1_4_DefOHTFId(int, typename DefOHTF<T>::ID);
template <class T>
void f1_5_DefOHTFId(int, const typename DefOHTF<T>::ID *);
template <class T>
void f1_6_DefOHTFId(int, volatile typename DefOHTF<T>::ID &);
template <class T>
void f1_1_DefOHTFIf(typename DefOHTF<T>::IC);
template <class T>
void f1_2_DefOHTFIf(const typename DefOHTF<T>::IC *);
template <class T>
void f1_3_DefOHTFIf(volatile typename DefOHTF<T>::IC &);
template <class T>
void f1_4_DefOHTFIf(int, typename DefOHTF<T>::IC);
template <class T>
void f1_5_DefOHTFIf(int, const typename DefOHTF<T>::IC *);
template <class T>
void f1_6_DefOHTFIf(int, volatile typename DefOHTF<T>::IC &);
template <class T>
void f1_1_DecHTAN(DecHTAN<T>);
template <class T>
void f1_2_DecHTAN(const DecHTAN<T> *);
template <class T>
void f1_3_DecHTAN(volatile DecHTAN<T> &);
template <class T>
void f1_4_DecHTAN(int, DecHTAN<T>);
template <class T>
void f1_5_DecHTAN(int, const DecHTAN<T> *);
template <class T>
void f1_6_DecHTAN(int, volatile DecHTAN<T> &);
template <class T>
void f1_1_DefHTAN(DefHTAN<T>);
template <class T>
void f1_2_DefHTAN(const DefHTAN<T> *);
template <class T>
void f1_3_DefHTAN(volatile DefHTAN<T> &);
template <class T>
void f1_4_DefHTAN(int, DefHTAN<T>);
template <class T>
void f1_5_DefHTAN(int, const DefHTAN<T> *);
template <class T>
void f1_6_DefHTAN(int, volatile DefHTAN<T> &);
template <class T>
void f1_1_DefHTANId(typename DefHTAN<T>::ID);
template <class T>
void f1_2_DefHTANId(const typename DefHTAN<T>::ID *);
template <class T>
void f1_3_DefHTANId(volatile typename DefHTAN<T>::ID &);
template <class T>
void f1_4_DefHTANId(int, typename DefHTAN<T>::ID);
template <class T>
void f1_5_DefHTANId(int, const typename DefHTAN<T>::ID *);
template <class T>
void f1_6_DefHTANId(int, volatile typename DefHTAN<T>::ID &);
template <class T>
void f1_1_DefHTANIf(typename DefHTAN<T>::IC);
template <class T>
void f1_2_DefHTANIf(const typename DefHTAN<T>::IC *);
template <class T>
void f1_3_DefHTANIf(volatile typename DefHTAN<T>::IC &);
template <class T>
void f1_4_DefHTANIf(int, typename DefHTAN<T>::IC);
template <class T>
void f1_5_DefHTANIf(int, const typename DefHTAN<T>::IC *);
template <class T>
void f1_6_DefHTANIf(int, volatile typename DefHTAN<T>::IC &);
template <class T>
void f1_1_DecOHTAN(DecOHTAN<T>);
template <class T>
void f1_2_DecOHTAN(const DecOHTAN<T> *);
template <class T>
void f1_3_DecOHTAN(volatile DecOHTAN<T> &);
template <class T>
void f1_4_DecOHTAN(int, DecOHTAN<T>);
template <class T>
void f1_5_DecOHTAN(int, const DecOHTAN<T> *);
template <class T>
void f1_6_DecOHTAN(int, volatile DecOHTAN<T> &);
template <class T>
void f1_1_DefOHTAN(DefOHTAN<T>);
template <class T>
void f1_2_DefOHTAN(const DefOHTAN<T> *);
template <class T>
void f1_3_DefOHTAN(volatile DefOHTAN<T> &);
template <class T>
void f1_4_DefOHTAN(int, DefOHTAN<T>);
template <class T>
void f1_5_DefOHTAN(int, const DefOHTAN<T> *);
template <class T>
void f1_6_DefOHTAN(int, volatile DefOHTAN<T> &);
template <class T>
void f1_1_DefOHTANId(typename DefOHTAN<T>::ID);
template <class T>
void f1_2_DefOHTANId(const typename DefOHTAN<T>::ID *);
template <class T>
void f1_3_DefOHTANId(volatile typename DefOHTAN<T>::ID &);
template <class T>
void f1_4_DefOHTANId(int, typename DefOHTAN<T>::ID);
template <class T>
void f1_5_DefOHTANId(int, const typename DefOHTAN<T>::ID *);
template <class T>
void f1_6_DefOHTANId(int, volatile typename DefOHTAN<T>::ID &);
template <class T>
void f1_1_DefOHTANIf(typename DefOHTAN<T>::IC);
template <class T>
void f1_2_DefOHTANIf(const typename DefOHTAN<T>::IC *);
template <class T>
void f1_3_DefOHTANIf(volatile typename DefOHTAN<T>::IC &);
template <class T>
void f1_4_DefOHTANIf(int, typename DefOHTAN<T>::IC);
template <class T>
void f1_5_DefOHTANIf(int, const typename DefOHTAN<T>::IC *);
template <class T>
void f1_6_DefOHTANIf(int, volatile typename DefOHTAN<T>::IC &);
template <class T, template <class> class U>
void f1_7_DecHF(U<DecHF>);
template <class T, template <class> class U>
void f1_8_DecHF(U<const DecHF *>);
template <class T, template <class> class U>
void f1_9_DecHF(U<volatile DecHF &>);
template <class T, template <class> class U>
void f1_7_DefHF(U<DefHF>);
template <class T, template <class> class U>
void f1_8_DefHF(U<const DefHF *>);
template <class T, template <class> class U>
void f1_9_DefHF(U<volatile DefHF &>);
template <class T, template <class> class U>
void f1_7_DefHFId(U<DefHF::ID>);
template <class T, template <class> class U>
void f1_8_DefHFId(U<const DefHF::ID *>);
template <class T, template <class> class U>
void f1_9_DefHFId(U<volatile DefHF::ID &>);
template <class T, template <class> class U>
void f1_7_DefHFIf(U<DefHF::IC>);
template <class T, template <class> class U>
void f1_8_DefHFIf(U<const DefHF::IC *>);
template <class T, template <class> class U>
void f1_9_DefHFIf(U<volatile DefHF::IC &>);
template <class T, template <class> class U>
void f1_7_DecOHF(U<DecOHF>);
template <class T, template <class> class U>
void f1_8_DecOHF(U<const DecOHF *>);
template <class T, template <class> class U>
void f1_9_DecOHF(U<volatile DecOHF &>);
template <class T, template <class> class U>
void f1_7_DefOHF(U<DefOHF>);
template <class T, template <class> class U>
void f1_8_DefOHF(U<const DefOHF *>);
template <class T, template <class> class U>
void f1_9_DefOHF(U<volatile DefOHF &>);
template <class T, template <class> class U>
void f1_7_DefOHFId(U<DefOHF::ID>);
template <class T, template <class> class U>
void f1_8_DefOHFId(U<const DefOHF::ID *>);
template <class T, template <class> class U>
void f1_9_DefOHFId(U<volatile DefOHF::ID &>);
template <class T, template <class> class U>
void f1_7_DefOHFIf(U<DefOHF::IC>);
template <class T, template <class> class U>
void f1_8_DefOHFIf(U<const DefOHF::IC *>);
template <class T, template <class> class U>
void f1_9_DefOHFIf(U<volatile DefOHF::IC &>);
template <class T, template <class> class U>
void f1_7_DecHAN(U<DecHAN>);
template <class T, template <class> class U>
void f1_8_DecHAN(U<const DecHAN *>);
template <class T, template <class> class U>
void f1_9_DecHAN(U<volatile DecHAN &>);
template <class T, template <class> class U>
void f1_7_DefHAN(U<DefHAN>);
template <class T, template <class> class U>
void f1_8_DefHAN(U<const DefHAN *>);
template <class T, template <class> class U>
void f1_9_DefHAN(U<volatile DefHAN &>);
template <class T, template <class> class U>
void f1_7_DefHANId(U<DefHAN::ID>);
template <class T, template <class> class U>
void f1_8_DefHANId(U<const DefHAN::ID *>);
template <class T, template <class> class U>
void f1_9_DefHANId(U<volatile DefHAN::ID &>);
template <class T, template <class> class U>
void f1_7_DefHANIf(U<DefHAN::IC>);
template <class T, template <class> class U>
void f1_8_DefHANIf(U<const DefHAN::IC *>);
template <class T, template <class> class U>
void f1_9_DefHANIf(U<volatile DefHAN::IC &>);
template <class T, template <class> class U>
void f1_7_DecOHAN(U<DecOHAN>);
template <class T, template <class> class U>
void f1_8_DecOHAN(U<const DecOHAN *>);
template <class T, template <class> class U>
void f1_9_DecOHAN(U<volatile DecOHAN &>);
template <class T, template <class> class U>
void f1_7_DefOHAN(U<DefOHAN>);
template <class T, template <class> class U>
void f1_8_DefOHAN(U<const DefOHAN *>);
template <class T, template <class> class U>
void f1_9_DefOHAN(U<volatile DefOHAN &>);
template <class T, template <class> class U>
void f1_7_DefOHANId(U<DefOHAN::ID>);
template <class T, template <class> class U>
void f1_8_DefOHANId(U<const DefOHAN::ID *>);
template <class T, template <class> class U>
void f1_9_DefOHANId(U<volatile DefOHAN::ID &>);
template <class T, template <class> class U>
void f1_7_DefOHANIf(U<DefOHAN::IC>);
template <class T, template <class> class U>
void f1_8_DefOHANIf(U<const DefOHAN::IC *>);
template <class T, template <class> class U>
void f1_9_DefOHANIf(U<volatile DefOHAN::IC &>);
template <class T, template <class> class U>
void f1_7_DefYHF(U<DefYHF>);
template <class T, template <class> class U>
void f1_8_DefYHF(U<const DefYHF *>);
template <class T, template <class> class U>
void f1_9_DefYHF(U<volatile DefYHF &>);
template <class T, template <class> class U>
void f1_7_DecYHF(U<DecYHF>);
template <class T, template <class> class U>
void f1_8_DecYHF(U<const DecYHF *>);
template <class T, template <class> class U>
void f1_9_DecYHF(U<volatile DecYHF &>);
template <class T, template <class> class U>
void f1_7_DecHTF(U<DecHTF<T> >);
template <class T, template <class> class U>
void f1_8_DecHTF(U<const DecHTF<T> *>);
template <class T, template <class> class U>
void f1_9_DecHTF(U<volatile DecHTF<T> &>);
template <class T, template <class> class U>
void f1_7_DefHTF(U<DefHTF<T> >);
template <class T, template <class> class U>
void f1_8_DefHTF(U<const DefHTF<T> *>);
template <class T, template <class> class U>
void f1_9_DefHTF(U<volatile DefHTF<T> &>);
template <class T, template <class> class U>
void f1_7_DefHTFId(U<typename DefHTF<T>::ID>);
template <class T, template <class> class U>
void f1_8_DefHTFId(U<const typename DefHTF<T>::ID *>);
template <class T, template <class> class U>
void f1_9_DefHTFId(U<volatile typename DefHTF<T>::ID &>);
template <class T, template <class> class U>
void f1_7_DefHTFIf(U<typename DefHTF<T>::IC>);
template <class T, template <class> class U>
void f1_8_DefHTFIf(U<const typename DefHTF<T>::IC *>);
template <class T, template <class> class U>
void f1_9_DefHTFIf(U<volatile typename DefHTF<T>::IC &>);
template <class T, template <class> class U>
void f1_7_DecOHTF(U<DecOHTF<T> >);
template <class T, template <class> class U>
void f1_8_DecOHTF(U<const DecOHTF<T> *>);
template <class T, template <class> class U>
void f1_9_DecOHTF(U<volatile DecOHTF<T> &>);
template <class T, template <class> class U>
void f1_7_DefOHTF(U<DefOHTF<T> >);
template <class T, template <class> class U>
void f1_8_DefOHTF(U<const DefOHTF<T> *>);
template <class T, template <class> class U>
void f1_9_DefOHTF(U<volatile DefOHTF<T> &>);
template <class T, template <class> class U>
void f1_7_DefOHTFId(U<typename DefOHTF<T>::ID>);
template <class T, template <class> class U>
void f1_8_DefOHTFId(U<const typename DefOHTF<T>::ID *>);
template <class T, template <class> class U>
void f1_9_DefOHTFId(U<volatile typename DefOHTF<T>::ID &>);
template <class T, template <class> class U>
void f1_7_DefOHTFIf(U<typename DefOHTF<T>::IC>);
template <class T, template <class> class U>
void f1_8_DefOHTFIf(U<const typename DefOHTF<T>::IC *>);
template <class T, template <class> class U>
void f1_9_DefOHTFIf(U<volatile typename DefOHTF<T>::IC &>);
template <class T, template <class> class U>
void f1_7_DecHTAN(U<DecHTAN<T> >);
template <class T, template <class> class U>
void f1_8_DecHTAN(U<const DecHTAN<T> *>);
template <class T, template <class> class U>
void f1_9_DecHTAN(U<volatile DecHTAN<T> &>);
template <class T, template <class> class U>
void f1_7_DefHTAN(U<DefHTAN<T> >);
template <class T, template <class> class U>
void f1_8_DefHTAN(U<const DefHTAN<T> *>);
template <class T, template <class> class U>
void f1_9_DefHTAN(U<volatile DefHTAN<T> &>);
template <class T, template <class> class U>
void f1_7_DefHTANId(U<typename DefHTAN<T>::ID>);
template <class T, template <class> class U>
void f1_8_DefHTANId(U<const typename DefHTAN<T>::ID *>);
template <class T, template <class> class U>
void f1_9_DefHTANId(U<volatile typename DefHTAN<T>::ID &>);
template <class T, template <class> class U>
void f1_7_DefHTANIf(U<typename DefHTAN<T>::IC>);
template <class T, template <class> class U>
void f1_8_DefHTANIf(U<const typename DefHTAN<T>::IC *>);
template <class T, template <class> class U>
void f1_9_DefHTANIf(U<volatile typename DefHTAN<T>::IC &>);
template <class T, template <class> class U>
void f1_7_DecOHTAN(U<DecOHTAN<T> >);
template <class T, template <class> class U>
void f1_8_DecOHTAN(U<const DecOHTAN<T> *>);
template <class T, template <class> class U>
void f1_9_DecOHTAN(U<volatile DecOHTAN<T> &>);
template <class T, template <class> class U>
void f1_7_DefOHTAN(U<DefOHTAN<T> >);
template <class T, template <class> class U>
void f1_8_DefOHTAN(U<const DefOHTAN<T> *>);
template <class T, template <class> class U>
void f1_9_DefOHTAN(U<volatile DefOHTAN<T> &>);
template <class T, template <class> class U>
void f1_7_DefOHTANId(U<typename DefOHTAN<T>::ID>);
template <class T, template <class> class U>
void f1_8_DefOHTANId(U<const typename DefOHTAN<T>::ID *>);
template <class T, template <class> class U>
void f1_9_DefOHTANId(U<volatile typename DefOHTAN<T>::ID &>);
template <class T, template <class> class U>
void f1_7_DefOHTANIf(U<typename DefOHTAN<T>::IC>);
template <class T, template <class> class U>
void f1_8_DefOHTANIf(U<const typename DefOHTAN<T>::IC *>);
template <class T, template <class> class U>
void f1_9_DefOHTANIf(U<volatile typename DefOHTAN<T>::IC &>);

namespace N
{
void f1_1_DecHF(DecHF);
void f1_2_DecHF(const DecHF *);
void f1_3_DecHF(volatile DecHF &);
void f1_4_DecHF(int, DecHF);
void f1_5_DecHF(int, const DecHF *);
void f1_6_DecHF(int, volatile DecHF &);
void f1_1_DefHF(DefHF);
void f1_2_DefHF(const DefHF *);
void f1_3_DefHF(volatile DefHF &);
void f1_4_DefHF(int, DefHF);
void f1_5_DefHF(int, const DefHF *);
void f1_6_DefHF(int, volatile DefHF &);
void f1_1_DefHFId(DefHF::ID);
void f1_2_DefHFId(const DefHF::ID *);
void f1_3_DefHFId(volatile DefHF::ID &);
void f1_4_DefHFId(int, DefHF::ID);
void f1_5_DefHFId(int, const DefHF::ID *);
void f1_6_DefHFId(int, volatile DefHF::ID &);
void f1_1_DefHFIf(DefHF::IC);
void f1_2_DefHFIf(const DefHF::IC *);
void f1_3_DefHFIf(volatile DefHF::IC &);
void f1_4_DefHFIf(int, DefHF::IC);
void f1_5_DefHFIf(int, const DefHF::IC *);
void f1_6_DefHFIf(int, volatile DefHF::IC &);
void f1_1_DecOHF(DecOHF);
void f1_2_DecOHF(const DecOHF *);
void f1_3_DecOHF(volatile DecOHF &);
void f1_4_DecOHF(int, DecOHF);
void f1_5_DecOHF(int, const DecOHF *);
void f1_6_DecOHF(int, volatile DecOHF &);
void f1_1_DefOHF(DefOHF);
void f1_2_DefOHF(const DefOHF *);
void f1_3_DefOHF(volatile DefOHF &);
void f1_4_DefOHF(int, DefOHF);
void f1_5_DefOHF(int, const DefOHF *);
void f1_6_DefOHF(int, volatile DefOHF &);
void f1_1_DefOHFId(DefOHF::ID);
void f1_2_DefOHFId(const DefOHF::ID *);
void f1_3_DefOHFId(volatile DefOHF::ID &);
void f1_4_DefOHFId(int, DefOHF::ID);
void f1_5_DefOHFId(int, const DefOHF::ID *);
void f1_6_DefOHFId(int, volatile DefOHF::ID &);
void f1_1_DefOHFIf(DefOHF::IC);
void f1_2_DefOHFIf(const DefOHF::IC *);
void f1_3_DefOHFIf(volatile DefOHF::IC &);
void f1_4_DefOHFIf(int, DefOHF::IC);
void f1_5_DefOHFIf(int, const DefOHF::IC *);
void f1_6_DefOHFIf(int, volatile DefOHF::IC &);
void f1_1_DecHAN(DecHAN);
void f1_2_DecHAN(const DecHAN *);
void f1_3_DecHAN(volatile DecHAN &);
void f1_4_DecHAN(int, DecHAN);
void f1_5_DecHAN(int, const DecHAN *);
void f1_6_DecHAN(int, volatile DecHAN &);
void f1_1_DefHAN(DefHAN);
void f1_2_DefHAN(const DefHAN *);
void f1_3_DefHAN(volatile DefHAN &);
void f1_4_DefHAN(int, DefHAN);
void f1_5_DefHAN(int, const DefHAN *);
void f1_6_DefHAN(int, volatile DefHAN &);
void f1_1_DefHANId(DefHAN::ID);
void f1_2_DefHANId(const DefHAN::ID *);
void f1_3_DefHANId(volatile DefHAN::ID &);
void f1_4_DefHANId(int, DefHAN::ID);
void f1_5_DefHANId(int, const DefHAN::ID *);
void f1_6_DefHANId(int, volatile DefHAN::ID &);
void f1_1_DefHANIf(DefHAN::IC);
void f1_2_DefHANIf(const DefHAN::IC *);
void f1_3_DefHANIf(volatile DefHAN::IC &);
void f1_4_DefHANIf(int, DefHAN::IC);
void f1_5_DefHANIf(int, const DefHAN::IC *);
void f1_6_DefHANIf(int, volatile DefHAN::IC &);
void f1_1_DecOHAN(DecOHAN);
void f1_2_DecOHAN(const DecOHAN *);
void f1_3_DecOHAN(volatile DecOHAN &);
void f1_4_DecOHAN(int, DecOHAN);
void f1_5_DecOHAN(int, const DecOHAN *);
void f1_6_DecOHAN(int, volatile DecOHAN &);
void f1_1_DefOHAN(DefOHAN);
void f1_2_DefOHAN(const DefOHAN *);
void f1_3_DefOHAN(volatile DefOHAN &);
void f1_4_DefOHAN(int, DefOHAN);
void f1_5_DefOHAN(int, const DefOHAN *);
void f1_6_DefOHAN(int, volatile DefOHAN &);
void f1_1_DefOHANId(DefOHAN::ID);
void f1_2_DefOHANId(const DefOHAN::ID *);
void f1_3_DefOHANId(volatile DefOHAN::ID &);
void f1_4_DefOHANId(int, DefOHAN::ID);
void f1_5_DefOHANId(int, const DefOHAN::ID *);
void f1_6_DefOHANId(int, volatile DefOHAN::ID &);
void f1_1_DefOHANIf(DefOHAN::IC);
void f1_2_DefOHANIf(const DefOHAN::IC *);
void f1_3_DefOHANIf(volatile DefOHAN::IC &);
void f1_4_DefOHANIf(int, DefOHAN::IC);
void f1_5_DefOHANIf(int, const DefOHAN::IC *);
void f1_6_DefOHANIf(int, volatile DefOHAN::IC &);
void f1_1_DefYHF(DefYHF);
void f1_2_DefYHF(const DefYHF *);
void f1_3_DefYHF(volatile DefYHF &);
void f1_4_DefYHF(int, DefYHF);
void f1_5_DefYHF(int, const DefYHF *);
void f1_6_DefYHF(int, volatile DefYHF &);
void f1_1_DecYHF(DecYHF);
void f1_2_DecYHF(const DecYHF *);
void f1_3_DecYHF(volatile DecYHF &);
void f1_4_DecYHF(int, DecYHF);
void f1_5_DecYHF(int, const DecYHF *);
void f1_6_DecYHF(int, volatile DecYHF &);
template <class T>
void f1_1_DecHTF(DecHTF<T>);
template <class T>
void f1_2_DecHTF(const DecHTF<T> *);
template <class T>
void f1_3_DecHTF(volatile DecHTF<T> &);
template <class T>
void f1_4_DecHTF(int, DecHTF<T>);
template <class T>
void f1_5_DecHTF(int, const DecHTF<T> *);
template <class T>
void f1_6_DecHTF(int, volatile DecHTF<T> &);
template <class T>
void f1_1_DefHTF(DefHTF<T>);
template <class T>
void f1_2_DefHTF(const DefHTF<T> *);
template <class T>
void f1_3_DefHTF(volatile DefHTF<T> &);
template <class T>
void f1_4_DefHTF(int, DefHTF<T>);
template <class T>
void f1_5_DefHTF(int, const DefHTF<T> *);
template <class T>
void f1_6_DefHTF(int, volatile DefHTF<T> &);
template <class T>
void f1_1_DefHTFId(typename DefHTF<T>::ID);
template <class T>
void f1_2_DefHTFId(const typename DefHTF<T>::ID *);
template <class T>
void f1_3_DefHTFId(volatile typename DefHTF<T>::ID &);
template <class T>
void f1_4_DefHTFId(int, typename DefHTF<T>::ID);
template <class T>
void f1_5_DefHTFId(int, const typename DefHTF<T>::ID *);
template <class T>
void f1_6_DefHTFId(int, volatile typename DefHTF<T>::ID &);
template <class T>
void f1_1_DefHTFIf(typename DefHTF<T>::IC);
template <class T>
void f1_2_DefHTFIf(const typename DefHTF<T>::IC *);
template <class T>
void f1_3_DefHTFIf(volatile typename DefHTF<T>::IC &);
template <class T>
void f1_4_DefHTFIf(int, typename DefHTF<T>::IC);
template <class T>
void f1_5_DefHTFIf(int, const typename DefHTF<T>::IC *);
template <class T>
void f1_6_DefHTFIf(int, volatile typename DefHTF<T>::IC &);
template <class T>
void f1_1_DecOHTF(DecOHTF<T>);
template <class T>
void f1_2_DecOHTF(const DecOHTF<T> *);
template <class T>
void f1_3_DecOHTF(volatile DecOHTF<T> &);
template <class T>
void f1_4_DecOHTF(int, DecOHTF<T>);
template <class T>
void f1_5_DecOHTF(int, const DecOHTF<T> *);
template <class T>
void f1_6_DecOHTF(int, volatile DecOHTF<T> &);
template <class T>
void f1_1_DefOHTF(DefOHTF<T>);
template <class T>
void f1_2_DefOHTF(const DefOHTF<T> *);
template <class T>
void f1_3_DefOHTF(volatile DefOHTF<T> &);
template <class T>
void f1_4_DefOHTF(int, DefOHTF<T>);
template <class T>
void f1_5_DefOHTF(int, const DefOHTF<T> *);
template <class T>
void f1_6_DefOHTF(int, volatile DefOHTF<T> &);
template <class T>
void f1_1_DefOHTFId(typename DefOHTF<T>::ID);
template <class T>
void f1_2_DefOHTFId(const typename DefOHTF<T>::ID *);
template <class T>
void f1_3_DefOHTFId(volatile typename DefOHTF<T>::ID &);
template <class T>
void f1_4_DefOHTFId(int, typename DefOHTF<T>::ID);
template <class T>
void f1_5_DefOHTFId(int, const typename DefOHTF<T>::ID *);
template <class T>
void f1_6_DefOHTFId(int, volatile typename DefOHTF<T>::ID &);
template <class T>
void f1_1_DefOHTFIf(typename DefOHTF<T>::IC);
template <class T>
void f1_2_DefOHTFIf(const typename DefOHTF<T>::IC *);
template <class T>
void f1_3_DefOHTFIf(volatile typename DefOHTF<T>::IC &);
template <class T>
void f1_4_DefOHTFIf(int, typename DefOHTF<T>::IC);
template <class T>
void f1_5_DefOHTFIf(int, const typename DefOHTF<T>::IC *);
template <class T>
void f1_6_DefOHTFIf(int, volatile typename DefOHTF<T>::IC &);
template <class T>
void f1_1_DecHTAN(DecHTAN<T>);
template <class T>
void f1_2_DecHTAN(const DecHTAN<T> *);
template <class T>
void f1_3_DecHTAN(volatile DecHTAN<T> &);
template <class T>
void f1_4_DecHTAN(int, DecHTAN<T>);
template <class T>
void f1_5_DecHTAN(int, const DecHTAN<T> *);
template <class T>
void f1_6_DecHTAN(int, volatile DecHTAN<T> &);
template <class T>
void f1_1_DefHTAN(DefHTAN<T>);
template <class T>
void f1_2_DefHTAN(const DefHTAN<T> *);
template <class T>
void f1_3_DefHTAN(volatile DefHTAN<T> &);
template <class T>
void f1_4_DefHTAN(int, DefHTAN<T>);
template <class T>
void f1_5_DefHTAN(int, const DefHTAN<T> *);
template <class T>
void f1_6_DefHTAN(int, volatile DefHTAN<T> &);
template <class T>
void f1_1_DefHTANId(typename DefHTAN<T>::ID);
template <class T>
void f1_2_DefHTANId(const typename DefHTAN<T>::ID *);
template <class T>
void f1_3_DefHTANId(volatile typename DefHTAN<T>::ID &);
template <class T>
void f1_4_DefHTANId(int, typename DefHTAN<T>::ID);
template <class T>
void f1_5_DefHTANId(int, const typename DefHTAN<T>::ID *);
template <class T>
void f1_6_DefHTANId(int, volatile typename DefHTAN<T>::ID &);
template <class T>
void f1_1_DefHTANIf(typename DefHTAN<T>::IC);
template <class T>
void f1_2_DefHTANIf(const typename DefHTAN<T>::IC *);
template <class T>
void f1_3_DefHTANIf(volatile typename DefHTAN<T>::IC &);
template <class T>
void f1_4_DefHTANIf(int, typename DefHTAN<T>::IC);
template <class T>
void f1_5_DefHTANIf(int, const typename DefHTAN<T>::IC *);
template <class T>
void f1_6_DefHTANIf(int, volatile typename DefHTAN<T>::IC &);
template <class T>
void f1_1_DecOHTAN(DecOHTAN<T>);
template <class T>
void f1_2_DecOHTAN(const DecOHTAN<T> *);
template <class T>
void f1_3_DecOHTAN(volatile DecOHTAN<T> &);
template <class T>
void f1_4_DecOHTAN(int, DecOHTAN<T>);
template <class T>
void f1_5_DecOHTAN(int, const DecOHTAN<T> *);
template <class T>
void f1_6_DecOHTAN(int, volatile DecOHTAN<T> &);
template <class T>
void f1_1_DefOHTAN(DefOHTAN<T>);
template <class T>
void f1_2_DefOHTAN(const DefOHTAN<T> *);
template <class T>
void f1_3_DefOHTAN(volatile DefOHTAN<T> &);
template <class T>
void f1_4_DefOHTAN(int, DefOHTAN<T>);
template <class T>
void f1_5_DefOHTAN(int, const DefOHTAN<T> *);
template <class T>
void f1_6_DefOHTAN(int, volatile DefOHTAN<T> &);
template <class T>
void f1_1_DefOHTANId(typename DefOHTAN<T>::ID);
template <class T>
void f1_2_DefOHTANId(const typename DefOHTAN<T>::ID *);
template <class T>
void f1_3_DefOHTANId(volatile typename DefOHTAN<T>::ID &);
template <class T>
void f1_4_DefOHTANId(int, typename DefOHTAN<T>::ID);
template <class T>
void f1_5_DefOHTANId(int, const typename DefOHTAN<T>::ID *);
template <class T>
void f1_6_DefOHTANId(int, volatile typename DefOHTAN<T>::ID &);
template <class T>
void f1_1_DefOHTANIf(typename DefOHTAN<T>::IC);
template <class T>
void f1_2_DefOHTANIf(const typename DefOHTAN<T>::IC *);
template <class T>
void f1_3_DefOHTANIf(volatile typename DefOHTAN<T>::IC &);
template <class T>
void f1_4_DefOHTANIf(int, typename DefOHTAN<T>::IC);
template <class T>
void f1_5_DefOHTANIf(int, const typename DefOHTAN<T>::IC *);
template <class T>
void f1_6_DefOHTANIf(int, volatile typename DefOHTAN<T>::IC &);
template <class T, template <class> class U>
void f1_7_DecHF(U<DecHF>);
template <class T, template <class> class U>
void f1_8_DecHF(U<const DecHF *>);
template <class T, template <class> class U>
void f1_9_DecHF(U<volatile DecHF &>);
template <class T, template <class> class U>
void f1_7_DefHF(U<DefHF>);
template <class T, template <class> class U>
void f1_8_DefHF(U<const DefHF *>);
template <class T, template <class> class U>
void f1_9_DefHF(U<volatile DefHF &>);
template <class T, template <class> class U>
void f1_7_DefHFId(U<DefHF::ID>);
template <class T, template <class> class U>
void f1_8_DefHFId(U<const DefHF::ID *>);
template <class T, template <class> class U>
void f1_9_DefHFId(U<volatile DefHF::ID &>);
template <class T, template <class> class U>
void f1_7_DefHFIf(U<DefHF::IC>);
template <class T, template <class> class U>
void f1_8_DefHFIf(U<const DefHF::IC *>);
template <class T, template <class> class U>
void f1_9_DefHFIf(U<volatile DefHF::IC &>);
template <class T, template <class> class U>
void f1_7_DecOHF(U<DecOHF>);
template <class T, template <class> class U>
void f1_8_DecOHF(U<const DecOHF *>);
template <class T, template <class> class U>
void f1_9_DecOHF(U<volatile DecOHF &>);
template <class T, template <class> class U>
void f1_7_DefOHF(U<DefOHF>);
template <class T, template <class> class U>
void f1_8_DefOHF(U<const DefOHF *>);
template <class T, template <class> class U>
void f1_9_DefOHF(U<volatile DefOHF &>);
template <class T, template <class> class U>
void f1_7_DefOHFId(U<DefOHF::ID>);
template <class T, template <class> class U>
void f1_8_DefOHFId(U<const DefOHF::ID *>);
template <class T, template <class> class U>
void f1_9_DefOHFId(U<volatile DefOHF::ID &>);
template <class T, template <class> class U>
void f1_7_DefOHFIf(U<DefOHF::IC>);
template <class T, template <class> class U>
void f1_8_DefOHFIf(U<const DefOHF::IC *>);
template <class T, template <class> class U>
void f1_9_DefOHFIf(U<volatile DefOHF::IC &>);
template <class T, template <class> class U>
void f1_7_DecHAN(U<DecHAN>);
template <class T, template <class> class U>
void f1_8_DecHAN(U<const DecHAN *>);
template <class T, template <class> class U>
void f1_9_DecHAN(U<volatile DecHAN &>);
template <class T, template <class> class U>
void f1_7_DefHAN(U<DefHAN>);
template <class T, template <class> class U>
void f1_8_DefHAN(U<const DefHAN *>);
template <class T, template <class> class U>
void f1_9_DefHAN(U<volatile DefHAN &>);
template <class T, template <class> class U>
void f1_7_DefHANId(U<DefHAN::ID>);
template <class T, template <class> class U>
void f1_8_DefHANId(U<const DefHAN::ID *>);
template <class T, template <class> class U>
void f1_9_DefHANId(U<volatile DefHAN::ID &>);
template <class T, template <class> class U>
void f1_7_DefHANIf(U<DefHAN::IC>);
template <class T, template <class> class U>
void f1_8_DefHANIf(U<const DefHAN::IC *>);
template <class T, template <class> class U>
void f1_9_DefHANIf(U<volatile DefHAN::IC &>);
template <class T, template <class> class U>
void f1_7_DecOHAN(U<DecOHAN>);
template <class T, template <class> class U>
void f1_8_DecOHAN(U<const DecOHAN *>);
template <class T, template <class> class U>
void f1_9_DecOHAN(U<volatile DecOHAN &>);
template <class T, template <class> class U>
void f1_7_DefOHAN(U<DefOHAN>);
template <class T, template <class> class U>
void f1_8_DefOHAN(U<const DefOHAN *>);
template <class T, template <class> class U>
void f1_9_DefOHAN(U<volatile DefOHAN &>);
template <class T, template <class> class U>
void f1_7_DefOHANId(U<DefOHAN::ID>);
template <class T, template <class> class U>
void f1_8_DefOHANId(U<const DefOHAN::ID *>);
template <class T, template <class> class U>
void f1_9_DefOHANId(U<volatile DefOHAN::ID &>);
template <class T, template <class> class U>
void f1_7_DefOHANIf(U<DefOHAN::IC>);
template <class T, template <class> class U>
void f1_8_DefOHANIf(U<const DefOHAN::IC *>);
template <class T, template <class> class U>
void f1_9_DefOHANIf(U<volatile DefOHAN::IC &>);
template <class T, template <class> class U>
void f1_7_DefYHF(U<DefYHF>);
template <class T, template <class> class U>
void f1_8_DefYHF(U<const DefYHF *>);
template <class T, template <class> class U>
void f1_9_DefYHF(U<volatile DefYHF &>);
template <class T, template <class> class U>
void f1_7_DecYHF(U<DecYHF>);
template <class T, template <class> class U>
void f1_8_DecYHF(U<const DecYHF *>);
template <class T, template <class> class U>
void f1_9_DecYHF(U<volatile DecYHF &>);
template <class T, template <class> class U>
void f1_7_DecHTF(U<DecHTF<T> >);
template <class T, template <class> class U>
void f1_8_DecHTF(U<const DecHTF<T> *>);
template <class T, template <class> class U>
void f1_9_DecHTF(U<volatile DecHTF<T> &>);
template <class T, template <class> class U>
void f1_7_DefHTF(U<DefHTF<T> >);
template <class T, template <class> class U>
void f1_8_DefHTF(U<const DefHTF<T> *>);
template <class T, template <class> class U>
void f1_9_DefHTF(U<volatile DefHTF<T> &>);
template <class T, template <class> class U>
void f1_7_DefHTFId(U<typename DefHTF<T>::ID>);
template <class T, template <class> class U>
void f1_8_DefHTFId(U<const typename DefHTF<T>::ID *>);
template <class T, template <class> class U>
void f1_9_DefHTFId(U<volatile typename DefHTF<T>::ID &>);
template <class T, template <class> class U>
void f1_7_DefHTFIf(U<typename DefHTF<T>::IC>);
template <class T, template <class> class U>
void f1_8_DefHTFIf(U<const typename DefHTF<T>::IC *>);
template <class T, template <class> class U>
void f1_9_DefHTFIf(U<volatile typename DefHTF<T>::IC &>);
template <class T, template <class> class U>
void f1_7_DecOHTF(U<DecOHTF<T> >);
template <class T, template <class> class U>
void f1_8_DecOHTF(U<const DecOHTF<T> *>);
template <class T, template <class> class U>
void f1_9_DecOHTF(U<volatile DecOHTF<T> &>);
template <class T, template <class> class U>
void f1_7_DefOHTF(U<DefOHTF<T> >);
template <class T, template <class> class U>
void f1_8_DefOHTF(U<const DefOHTF<T> *>);
template <class T, template <class> class U>
void f1_9_DefOHTF(U<volatile DefOHTF<T> &>);
template <class T, template <class> class U>
void f1_7_DefOHTFId(U<typename DefOHTF<T>::ID>);
template <class T, template <class> class U>
void f1_8_DefOHTFId(U<const typename DefOHTF<T>::ID *>);
template <class T, template <class> class U>
void f1_9_DefOHTFId(U<volatile typename DefOHTF<T>::ID &>);
template <class T, template <class> class U>
void f1_7_DefOHTFIf(U<typename DefOHTF<T>::IC>);
template <class T, template <class> class U>
void f1_8_DefOHTFIf(U<const typename DefOHTF<T>::IC *>);
template <class T, template <class> class U>
void f1_9_DefOHTFIf(U<volatile typename DefOHTF<T>::IC &>);
template <class T, template <class> class U>
void f1_7_DecHTAN(U<DecHTAN<T> >);
template <class T, template <class> class U>
void f1_8_DecHTAN(U<const DecHTAN<T> *>);
template <class T, template <class> class U>
void f1_9_DecHTAN(U<volatile DecHTAN<T> &>);
template <class T, template <class> class U>
void f1_7_DefHTAN(U<DefHTAN<T> >);
template <class T, template <class> class U>
void f1_8_DefHTAN(U<const DefHTAN<T> *>);
template <class T, template <class> class U>
void f1_9_DefHTAN(U<volatile DefHTAN<T> &>);
template <class T, template <class> class U>
void f1_7_DefHTANId(U<typename DefHTAN<T>::ID>);
template <class T, template <class> class U>
void f1_8_DefHTANId(U<const typename DefHTAN<T>::ID *>);
template <class T, template <class> class U>
void f1_9_DefHTANId(U<volatile typename DefHTAN<T>::ID &>);
template <class T, template <class> class U>
void f1_7_DefHTANIf(U<typename DefHTAN<T>::IC>);
template <class T, template <class> class U>
void f1_8_DefHTANIf(U<const typename DefHTAN<T>::IC *>);
template <class T, template <class> class U>
void f1_9_DefHTANIf(U<volatile typename DefHTAN<T>::IC &>);
template <class T, template <class> class U>
void f1_7_DecOHTAN(U<DecOHTAN<T> >);
template <class T, template <class> class U>
void f1_8_DecOHTAN(U<const DecOHTAN<T> *>);
template <class T, template <class> class U>
void f1_9_DecOHTAN(U<volatile DecOHTAN<T> &>);
template <class T, template <class> class U>
void f1_7_DefOHTAN(U<DefOHTAN<T> >);
template <class T, template <class> class U>
void f1_8_DefOHTAN(U<const DefOHTAN<T> *>);
template <class T, template <class> class U>
void f1_9_DefOHTAN(U<volatile DefOHTAN<T> &>);
template <class T, template <class> class U>
void f1_7_DefOHTANId(U<typename DefOHTAN<T>::ID>);
template <class T, template <class> class U>
void f1_8_DefOHTANId(U<const typename DefOHTAN<T>::ID *>);
template <class T, template <class> class U>
void f1_9_DefOHTANId(U<volatile typename DefOHTAN<T>::ID &>);
template <class T, template <class> class U>
void f1_7_DefOHTANIf(U<typename DefOHTAN<T>::IC>);
template <class T, template <class> class U>
void f1_8_DefOHTANIf(U<const typename DefOHTAN<T>::IC *>);
template <class T, template <class> class U>
void f1_9_DefOHTANIf(U<volatile typename DefOHTAN<T>::IC &>);
}

struct E {
    void f1_1_DecHF(DecHF);
    void f1_2_DecHF(const DecHF *);
    void f1_3_DecHF(volatile DecHF &);
    void f1_4_DecHF(int, DecHF);
    void f1_5_DecHF(int, const DecHF *);
    void f1_6_DecHF(int, volatile DecHF &);
    void f1_1_DefHF(DefHF);
    void f1_2_DefHF(const DefHF *);
    void f1_3_DefHF(volatile DefHF &);
    void f1_4_DefHF(int, DefHF);
    void f1_5_DefHF(int, const DefHF *);
    void f1_6_DefHF(int, volatile DefHF &);
    void f1_1_DefHFId(DefHF::ID);
    void f1_2_DefHFId(const DefHF::ID *);
    void f1_3_DefHFId(volatile DefHF::ID &);
    void f1_4_DefHFId(int, DefHF::ID);
    void f1_5_DefHFId(int, const DefHF::ID *);
    void f1_6_DefHFId(int, volatile DefHF::ID &);
    void f1_1_DefHFIf(DefHF::IC);
    void f1_2_DefHFIf(const DefHF::IC *);
    void f1_3_DefHFIf(volatile DefHF::IC &);
    void f1_4_DefHFIf(int, DefHF::IC);
    void f1_5_DefHFIf(int, const DefHF::IC *);
    void f1_6_DefHFIf(int, volatile DefHF::IC &);
    void f1_1_DecOHF(DecOHF);
    void f1_2_DecOHF(const DecOHF *);
    void f1_3_DecOHF(volatile DecOHF &);
    void f1_4_DecOHF(int, DecOHF);
    void f1_5_DecOHF(int, const DecOHF *);
    void f1_6_DecOHF(int, volatile DecOHF &);
    void f1_1_DefOHF(DefOHF);
    void f1_2_DefOHF(const DefOHF *);
    void f1_3_DefOHF(volatile DefOHF &);
    void f1_4_DefOHF(int, DefOHF);
    void f1_5_DefOHF(int, const DefOHF *);
    void f1_6_DefOHF(int, volatile DefOHF &);
    void f1_1_DefOHFId(DefOHF::ID);
    void f1_2_DefOHFId(const DefOHF::ID *);
    void f1_3_DefOHFId(volatile DefOHF::ID &);
    void f1_4_DefOHFId(int, DefOHF::ID);
    void f1_5_DefOHFId(int, const DefOHF::ID *);
    void f1_6_DefOHFId(int, volatile DefOHF::ID &);
    void f1_1_DefOHFIf(DefOHF::IC);
    void f1_2_DefOHFIf(const DefOHF::IC *);
    void f1_3_DefOHFIf(volatile DefOHF::IC &);
    void f1_4_DefOHFIf(int, DefOHF::IC);
    void f1_5_DefOHFIf(int, const DefOHF::IC *);
    void f1_6_DefOHFIf(int, volatile DefOHF::IC &);
    void f1_1_DecHAN(DecHAN);
    void f1_2_DecHAN(const DecHAN *);
    void f1_3_DecHAN(volatile DecHAN &);
    void f1_4_DecHAN(int, DecHAN);
    void f1_5_DecHAN(int, const DecHAN *);
    void f1_6_DecHAN(int, volatile DecHAN &);
    void f1_1_DefHAN(DefHAN);
    void f1_2_DefHAN(const DefHAN *);
    void f1_3_DefHAN(volatile DefHAN &);
    void f1_4_DefHAN(int, DefHAN);
    void f1_5_DefHAN(int, const DefHAN *);
    void f1_6_DefHAN(int, volatile DefHAN &);
    void f1_1_DefHANId(DefHAN::ID);
    void f1_2_DefHANId(const DefHAN::ID *);
    void f1_3_DefHANId(volatile DefHAN::ID &);
    void f1_4_DefHANId(int, DefHAN::ID);
    void f1_5_DefHANId(int, const DefHAN::ID *);
    void f1_6_DefHANId(int, volatile DefHAN::ID &);
    void f1_1_DefHANIf(DefHAN::IC);
    void f1_2_DefHANIf(const DefHAN::IC *);
    void f1_3_DefHANIf(volatile DefHAN::IC &);
    void f1_4_DefHANIf(int, DefHAN::IC);
    void f1_5_DefHANIf(int, const DefHAN::IC *);
    void f1_6_DefHANIf(int, volatile DefHAN::IC &);
    void f1_1_DecOHAN(DecOHAN);
    void f1_2_DecOHAN(const DecOHAN *);
    void f1_3_DecOHAN(volatile DecOHAN &);
    void f1_4_DecOHAN(int, DecOHAN);
    void f1_5_DecOHAN(int, const DecOHAN *);
    void f1_6_DecOHAN(int, volatile DecOHAN &);
    void f1_1_DefOHAN(DefOHAN);
    void f1_2_DefOHAN(const DefOHAN *);
    void f1_3_DefOHAN(volatile DefOHAN &);
    void f1_4_DefOHAN(int, DefOHAN);
    void f1_5_DefOHAN(int, const DefOHAN *);
    void f1_6_DefOHAN(int, volatile DefOHAN &);
    void f1_1_DefOHANId(DefOHAN::ID);
    void f1_2_DefOHANId(const DefOHAN::ID *);
    void f1_3_DefOHANId(volatile DefOHAN::ID &);
    void f1_4_DefOHANId(int, DefOHAN::ID);
    void f1_5_DefOHANId(int, const DefOHAN::ID *);
    void f1_6_DefOHANId(int, volatile DefOHAN::ID &);
    void f1_1_DefOHANIf(DefOHAN::IC);
    void f1_2_DefOHANIf(const DefOHAN::IC *);
    void f1_3_DefOHANIf(volatile DefOHAN::IC &);
    void f1_4_DefOHANIf(int, DefOHAN::IC);
    void f1_5_DefOHANIf(int, const DefOHAN::IC *);
    void f1_6_DefOHANIf(int, volatile DefOHAN::IC &);
    void f1_1_DefYHF(DefYHF);
    void f1_2_DefYHF(const DefYHF *);
    void f1_3_DefYHF(volatile DefYHF &);
    void f1_4_DefYHF(int, DefYHF);
    void f1_5_DefYHF(int, const DefYHF *);
    void f1_6_DefYHF(int, volatile DefYHF &);
    void f1_1_DecYHF(DecYHF);
    void f1_2_DecYHF(const DecYHF *);
    void f1_3_DecYHF(volatile DecYHF &);
    void f1_4_DecYHF(int, DecYHF);
    void f1_5_DecYHF(int, const DecYHF *);
    void f1_6_DecYHF(int, volatile DecYHF &);
    template <class T>
    void f1_1_DecHTF(DecHTF<T>);
    template <class T>
    void f1_2_DecHTF(const DecHTF<T> *);
    template <class T>
    void f1_3_DecHTF(volatile DecHTF<T> &);
    template <class T>
    void f1_4_DecHTF(int, DecHTF<T>);
    template <class T>
    void f1_5_DecHTF(int, const DecHTF<T> *);
    template <class T>
    void f1_6_DecHTF(int, volatile DecHTF<T> &);
    template <class T>
    void f1_1_DefHTF(DefHTF<T>);
    template <class T>
    void f1_2_DefHTF(const DefHTF<T> *);
    template <class T>
    void f1_3_DefHTF(volatile DefHTF<T> &);
    template <class T>
    void f1_4_DefHTF(int, DefHTF<T>);
    template <class T>
    void f1_5_DefHTF(int, const DefHTF<T> *);
    template <class T>
    void f1_6_DefHTF(int, volatile DefHTF<T> &);
    template <class T>
    void f1_1_DefHTFId(typename DefHTF<T>::ID);
    template <class T>
    void f1_2_DefHTFId(const typename DefHTF<T>::ID *);
    template <class T>
    void f1_3_DefHTFId(volatile typename DefHTF<T>::ID &);
    template <class T>
    void f1_4_DefHTFId(int, typename DefHTF<T>::ID);
    template <class T>
    void f1_5_DefHTFId(int, const typename DefHTF<T>::ID *);
    template <class T>
    void f1_6_DefHTFId(int, volatile typename DefHTF<T>::ID &);
    template <class T>
    void f1_1_DefHTFIf(typename DefHTF<T>::IC);
    template <class T>
    void f1_2_DefHTFIf(const typename DefHTF<T>::IC *);
    template <class T>
    void f1_3_DefHTFIf(volatile typename DefHTF<T>::IC &);
    template <class T>
    void f1_4_DefHTFIf(int, typename DefHTF<T>::IC);
    template <class T>
    void f1_5_DefHTFIf(int, const typename DefHTF<T>::IC *);
    template <class T>
    void f1_6_DefHTFIf(int, volatile typename DefHTF<T>::IC &);
    template <class T>
    void f1_1_DecOHTF(DecOHTF<T>);
    template <class T>
    void f1_2_DecOHTF(const DecOHTF<T> *);
    template <class T>
    void f1_3_DecOHTF(volatile DecOHTF<T> &);
    template <class T>
    void f1_4_DecOHTF(int, DecOHTF<T>);
    template <class T>
    void f1_5_DecOHTF(int, const DecOHTF<T> *);
    template <class T>
    void f1_6_DecOHTF(int, volatile DecOHTF<T> &);
    template <class T>
    void f1_1_DefOHTF(DefOHTF<T>);
    template <class T>
    void f1_2_DefOHTF(const DefOHTF<T> *);
    template <class T>
    void f1_3_DefOHTF(volatile DefOHTF<T> &);
    template <class T>
    void f1_4_DefOHTF(int, DefOHTF<T>);
    template <class T>
    void f1_5_DefOHTF(int, const DefOHTF<T> *);
    template <class T>
    void f1_6_DefOHTF(int, volatile DefOHTF<T> &);
    template <class T>
    void f1_1_DefOHTFId(typename DefOHTF<T>::ID);
    template <class T>
    void f1_2_DefOHTFId(const typename DefOHTF<T>::ID *);
    template <class T>
    void f1_3_DefOHTFId(volatile typename DefOHTF<T>::ID &);
    template <class T>
    void f1_4_DefOHTFId(int, typename DefOHTF<T>::ID);
    template <class T>
    void f1_5_DefOHTFId(int, const typename DefOHTF<T>::ID *);
    template <class T>
    void f1_6_DefOHTFId(int, volatile typename DefOHTF<T>::ID &);
    template <class T>
    void f1_1_DefOHTFIf(typename DefOHTF<T>::IC);
    template <class T>
    void f1_2_DefOHTFIf(const typename DefOHTF<T>::IC *);
    template <class T>
    void f1_3_DefOHTFIf(volatile typename DefOHTF<T>::IC &);
    template <class T>
    void f1_4_DefOHTFIf(int, typename DefOHTF<T>::IC);
    template <class T>
    void f1_5_DefOHTFIf(int, const typename DefOHTF<T>::IC *);
    template <class T>
    void f1_6_DefOHTFIf(int, volatile typename DefOHTF<T>::IC &);
    template <class T>
    void f1_1_DecHTAN(DecHTAN<T>);
    template <class T>
    void f1_2_DecHTAN(const DecHTAN<T> *);
    template <class T>
    void f1_3_DecHTAN(volatile DecHTAN<T> &);
    template <class T>
    void f1_4_DecHTAN(int, DecHTAN<T>);
    template <class T>
    void f1_5_DecHTAN(int, const DecHTAN<T> *);
    template <class T>
    void f1_6_DecHTAN(int, volatile DecHTAN<T> &);
    template <class T>
    void f1_1_DefHTAN(DefHTAN<T>);
    template <class T>
    void f1_2_DefHTAN(const DefHTAN<T> *);
    template <class T>
    void f1_3_DefHTAN(volatile DefHTAN<T> &);
    template <class T>
    void f1_4_DefHTAN(int, DefHTAN<T>);
    template <class T>
    void f1_5_DefHTAN(int, const DefHTAN<T> *);
    template <class T>
    void f1_6_DefHTAN(int, volatile DefHTAN<T> &);
    template <class T>
    void f1_1_DefHTANId(typename DefHTAN<T>::ID);
    template <class T>
    void f1_2_DefHTANId(const typename DefHTAN<T>::ID *);
    template <class T>
    void f1_3_DefHTANId(volatile typename DefHTAN<T>::ID &);
    template <class T>
    void f1_4_DefHTANId(int, typename DefHTAN<T>::ID);
    template <class T>
    void f1_5_DefHTANId(int, const typename DefHTAN<T>::ID *);
    template <class T>
    void f1_6_DefHTANId(int, volatile typename DefHTAN<T>::ID &);
    template <class T>
    void f1_1_DefHTANIf(typename DefHTAN<T>::IC);
    template <class T>
    void f1_2_DefHTANIf(const typename DefHTAN<T>::IC *);
    template <class T>
    void f1_3_DefHTANIf(volatile typename DefHTAN<T>::IC &);
    template <class T>
    void f1_4_DefHTANIf(int, typename DefHTAN<T>::IC);
    template <class T>
    void f1_5_DefHTANIf(int, const typename DefHTAN<T>::IC *);
    template <class T>
    void f1_6_DefHTANIf(int, volatile typename DefHTAN<T>::IC &);
    template <class T>
    void f1_1_DecOHTAN(DecOHTAN<T>);
    template <class T>
    void f1_2_DecOHTAN(const DecOHTAN<T> *);
    template <class T>
    void f1_3_DecOHTAN(volatile DecOHTAN<T> &);
    template <class T>
    void f1_4_DecOHTAN(int, DecOHTAN<T>);
    template <class T>
    void f1_5_DecOHTAN(int, const DecOHTAN<T> *);
    template <class T>
    void f1_6_DecOHTAN(int, volatile DecOHTAN<T> &);
    template <class T>
    void f1_1_DefOHTAN(DefOHTAN<T>);
    template <class T>
    void f1_2_DefOHTAN(const DefOHTAN<T> *);
    template <class T>
    void f1_3_DefOHTAN(volatile DefOHTAN<T> &);
    template <class T>
    void f1_4_DefOHTAN(int, DefOHTAN<T>);
    template <class T>
    void f1_5_DefOHTAN(int, const DefOHTAN<T> *);
    template <class T>
    void f1_6_DefOHTAN(int, volatile DefOHTAN<T> &);
    template <class T>
    void f1_1_DefOHTANId(typename DefOHTAN<T>::ID);
    template <class T>
    void f1_2_DefOHTANId(const typename DefOHTAN<T>::ID *);
    template <class T>
    void f1_3_DefOHTANId(volatile typename DefOHTAN<T>::ID &);
    template <class T>
    void f1_4_DefOHTANId(int, typename DefOHTAN<T>::ID);
    template <class T>
    void f1_5_DefOHTANId(int, const typename DefOHTAN<T>::ID *);
    template <class T>
    void f1_6_DefOHTANId(int, volatile typename DefOHTAN<T>::ID &);
    template <class T>
    void f1_1_DefOHTANIf(typename DefOHTAN<T>::IC);
    template <class T>
    void f1_2_DefOHTANIf(const typename DefOHTAN<T>::IC *);
    template <class T>
    void f1_3_DefOHTANIf(volatile typename DefOHTAN<T>::IC &);
    template <class T>
    void f1_4_DefOHTANIf(int, typename DefOHTAN<T>::IC);
    template <class T>
    void f1_5_DefOHTANIf(int, const typename DefOHTAN<T>::IC *);
    template <class T>
    void f1_6_DefOHTANIf(int, volatile typename DefOHTAN<T>::IC &);
    template <class T, template <class> class U>
    void f1_7_DecHF(U<DecHF>);
    template <class T, template <class> class U>
    void f1_8_DecHF(U<const DecHF *>);
    template <class T, template <class> class U>
    void f1_9_DecHF(U<volatile DecHF &>);
    template <class T, template <class> class U>
    void f1_7_DefHF(U<DefHF>);
    template <class T, template <class> class U>
    void f1_8_DefHF(U<const DefHF *>);
    template <class T, template <class> class U>
    void f1_9_DefHF(U<volatile DefHF &>);
    template <class T, template <class> class U>
    void f1_7_DefHFId(U<DefHF::ID>);
    template <class T, template <class> class U>
    void f1_8_DefHFId(U<const DefHF::ID *>);
    template <class T, template <class> class U>
    void f1_9_DefHFId(U<volatile DefHF::ID &>);
    template <class T, template <class> class U>
    void f1_7_DefHFIf(U<DefHF::IC>);
    template <class T, template <class> class U>
    void f1_8_DefHFIf(U<const DefHF::IC *>);
    template <class T, template <class> class U>
    void f1_9_DefHFIf(U<volatile DefHF::IC &>);
    template <class T, template <class> class U>
    void f1_7_DecOHF(U<DecOHF>);
    template <class T, template <class> class U>
    void f1_8_DecOHF(U<const DecOHF *>);
    template <class T, template <class> class U>
    void f1_9_DecOHF(U<volatile DecOHF &>);
    template <class T, template <class> class U>
    void f1_7_DefOHF(U<DefOHF>);
    template <class T, template <class> class U>
    void f1_8_DefOHF(U<const DefOHF *>);
    template <class T, template <class> class U>
    void f1_9_DefOHF(U<volatile DefOHF &>);
    template <class T, template <class> class U>
    void f1_7_DefOHFId(U<DefOHF::ID>);
    template <class T, template <class> class U>
    void f1_8_DefOHFId(U<const DefOHF::ID *>);
    template <class T, template <class> class U>
    void f1_9_DefOHFId(U<volatile DefOHF::ID &>);
    template <class T, template <class> class U>
    void f1_7_DefOHFIf(U<DefOHF::IC>);
    template <class T, template <class> class U>
    void f1_8_DefOHFIf(U<const DefOHF::IC *>);
    template <class T, template <class> class U>
    void f1_9_DefOHFIf(U<volatile DefOHF::IC &>);
    template <class T, template <class> class U>
    void f1_7_DecHAN(U<DecHAN>);
    template <class T, template <class> class U>
    void f1_8_DecHAN(U<const DecHAN *>);
    template <class T, template <class> class U>
    void f1_9_DecHAN(U<volatile DecHAN &>);
    template <class T, template <class> class U>
    void f1_7_DefHAN(U<DefHAN>);
    template <class T, template <class> class U>
    void f1_8_DefHAN(U<const DefHAN *>);
    template <class T, template <class> class U>
    void f1_9_DefHAN(U<volatile DefHAN &>);
    template <class T, template <class> class U>
    void f1_7_DefHANId(U<DefHAN::ID>);
    template <class T, template <class> class U>
    void f1_8_DefHANId(U<const DefHAN::ID *>);
    template <class T, template <class> class U>
    void f1_9_DefHANId(U<volatile DefHAN::ID &>);
    template <class T, template <class> class U>
    void f1_7_DefHANIf(U<DefHAN::IC>);
    template <class T, template <class> class U>
    void f1_8_DefHANIf(U<const DefHAN::IC *>);
    template <class T, template <class> class U>
    void f1_9_DefHANIf(U<volatile DefHAN::IC &>);
    template <class T, template <class> class U>
    void f1_7_DecOHAN(U<DecOHAN>);
    template <class T, template <class> class U>
    void f1_8_DecOHAN(U<const DecOHAN *>);
    template <class T, template <class> class U>
    void f1_9_DecOHAN(U<volatile DecOHAN &>);
    template <class T, template <class> class U>
    void f1_7_DefOHAN(U<DefOHAN>);
    template <class T, template <class> class U>
    void f1_8_DefOHAN(U<const DefOHAN *>);
    template <class T, template <class> class U>
    void f1_9_DefOHAN(U<volatile DefOHAN &>);
    template <class T, template <class> class U>
    void f1_7_DefOHANId(U<DefOHAN::ID>);
    template <class T, template <class> class U>
    void f1_8_DefOHANId(U<const DefOHAN::ID *>);
    template <class T, template <class> class U>
    void f1_9_DefOHANId(U<volatile DefOHAN::ID &>);
    template <class T, template <class> class U>
    void f1_7_DefOHANIf(U<DefOHAN::IC>);
    template <class T, template <class> class U>
    void f1_8_DefOHANIf(U<const DefOHAN::IC *>);
    template <class T, template <class> class U>
    void f1_9_DefOHANIf(U<volatile DefOHAN::IC &>);
    template <class T, template <class> class U>
    void f1_7_DefYHF(U<DefYHF>);
    template <class T, template <class> class U>
    void f1_8_DefYHF(U<const DefYHF *>);
    template <class T, template <class> class U>
    void f1_9_DefYHF(U<volatile DefYHF &>);
    template <class T, template <class> class U>
    void f1_7_DecYHF(U<DecYHF>);
    template <class T, template <class> class U>
    void f1_8_DecYHF(U<const DecYHF *>);
    template <class T, template <class> class U>
    void f1_9_DecYHF(U<volatile DecYHF &>);
    template <class T, template <class> class U>
    void f1_7_DecHTF(U<DecHTF<T> >);
    template <class T, template <class> class U>
    void f1_8_DecHTF(U<const DecHTF<T> *>);
    template <class T, template <class> class U>
    void f1_9_DecHTF(U<volatile DecHTF<T> &>);
    template <class T, template <class> class U>
    void f1_7_DefHTF(U<DefHTF<T> >);
    template <class T, template <class> class U>
    void f1_8_DefHTF(U<const DefHTF<T> *>);
    template <class T, template <class> class U>
    void f1_9_DefHTF(U<volatile DefHTF<T> &>);
    template <class T, template <class> class U>
    void f1_7_DefHTFId(U<typename DefHTF<T>::ID>);
    template <class T, template <class> class U>
    void f1_8_DefHTFId(U<const typename DefHTF<T>::ID *>);
    template <class T, template <class> class U>
    void f1_9_DefHTFId(U<volatile typename DefHTF<T>::ID &>);
    template <class T, template <class> class U>
    void f1_7_DefHTFIf(U<typename DefHTF<T>::IC>);
    template <class T, template <class> class U>
    void f1_8_DefHTFIf(U<const typename DefHTF<T>::IC *>);
    template <class T, template <class> class U>
    void f1_9_DefHTFIf(U<volatile typename DefHTF<T>::IC &>);
    template <class T, template <class> class U>
    void f1_7_DecOHTF(U<DecOHTF<T> >);
    template <class T, template <class> class U>
    void f1_8_DecOHTF(U<const DecOHTF<T> *>);
    template <class T, template <class> class U>
    void f1_9_DecOHTF(U<volatile DecOHTF<T> &>);
    template <class T, template <class> class U>
    void f1_7_DefOHTF(U<DefOHTF<T> >);
    template <class T, template <class> class U>
    void f1_8_DefOHTF(U<const DefOHTF<T> *>);
    template <class T, template <class> class U>
    void f1_9_DefOHTF(U<volatile DefOHTF<T> &>);
    template <class T, template <class> class U>
    void f1_7_DefOHTFId(U<typename DefOHTF<T>::ID>);
    template <class T, template <class> class U>
    void f1_8_DefOHTFId(U<const typename DefOHTF<T>::ID *>);
    template <class T, template <class> class U>
    void f1_9_DefOHTFId(U<volatile typename DefOHTF<T>::ID &>);
    template <class T, template <class> class U>
    void f1_7_DefOHTFIf(U<typename DefOHTF<T>::IC>);
    template <class T, template <class> class U>
    void f1_8_DefOHTFIf(U<const typename DefOHTF<T>::IC *>);
    template <class T, template <class> class U>
    void f1_9_DefOHTFIf(U<volatile typename DefOHTF<T>::IC &>);
    template <class T, template <class> class U>
    void f1_7_DecHTAN(U<DecHTAN<T> >);
    template <class T, template <class> class U>
    void f1_8_DecHTAN(U<const DecHTAN<T> *>);
    template <class T, template <class> class U>
    void f1_9_DecHTAN(U<volatile DecHTAN<T> &>);
    template <class T, template <class> class U>
    void f1_7_DefHTAN(U<DefHTAN<T> >);
    template <class T, template <class> class U>
    void f1_8_DefHTAN(U<const DefHTAN<T> *>);
    template <class T, template <class> class U>
    void f1_9_DefHTAN(U<volatile DefHTAN<T> &>);
    template <class T, template <class> class U>
    void f1_7_DefHTANId(U<typename DefHTAN<T>::ID>);
    template <class T, template <class> class U>
    void f1_8_DefHTANId(U<const typename DefHTAN<T>::ID *>);
    template <class T, template <class> class U>
    void f1_9_DefHTANId(U<volatile typename DefHTAN<T>::ID &>);
    template <class T, template <class> class U>
    void f1_7_DefHTANIf(U<typename DefHTAN<T>::IC>);
    template <class T, template <class> class U>
    void f1_8_DefHTANIf(U<const typename DefHTAN<T>::IC *>);
    template <class T, template <class> class U>
    void f1_9_DefHTANIf(U<volatile typename DefHTAN<T>::IC &>);
    template <class T, template <class> class U>
    void f1_7_DecOHTAN(U<DecOHTAN<T> >);
    template <class T, template <class> class U>
    void f1_8_DecOHTAN(U<const DecOHTAN<T> *>);
    template <class T, template <class> class U>
    void f1_9_DecOHTAN(U<volatile DecOHTAN<T> &>);
    template <class T, template <class> class U>
    void f1_7_DefOHTAN(U<DefOHTAN<T> >);
    template <class T, template <class> class U>
    void f1_8_DefOHTAN(U<const DefOHTAN<T> *>);
    template <class T, template <class> class U>
    void f1_9_DefOHTAN(U<volatile DefOHTAN<T> &>);
    template <class T, template <class> class U>
    void f1_7_DefOHTANId(U<typename DefOHTAN<T>::ID>);
    template <class T, template <class> class U>
    void f1_8_DefOHTANId(U<const typename DefOHTAN<T>::ID *>);
    template <class T, template <class> class U>
    void f1_9_DefOHTANId(U<volatile typename DefOHTAN<T>::ID &>);
    template <class T, template <class> class U>
    void f1_7_DefOHTANIf(U<typename DefOHTAN<T>::IC>);
    template <class T, template <class> class U>
    void f1_8_DefOHTANIf(U<const typename DefOHTAN<T>::IC *>);
    template <class T, template <class> class U>
    void f1_9_DefOHTANIf(U<volatile typename DefOHTAN<T>::IC &>);
};

extern "C++" {
void f2_1_DecHF(DecHF);
void f2_2_DecHF(const DecHF *);
void f2_3_DecHF(volatile DecHF &);
void f2_4_DecHF(int, DecHF);
void f2_5_DecHF(int, const DecHF *);
void f2_6_DecHF(int, volatile DecHF &);
void f2_1_DefHF(DefHF);
void f2_2_DefHF(const DefHF *);
void f2_3_DefHF(volatile DefHF &);
void f2_4_DefHF(int, DefHF);
void f2_5_DefHF(int, const DefHF *);
void f2_6_DefHF(int, volatile DefHF &);
void f2_1_DefHFId(DefHF::ID);
void f2_2_DefHFId(const DefHF::ID *);
void f2_3_DefHFId(volatile DefHF::ID &);
void f2_4_DefHFId(int, DefHF::ID);
void f2_5_DefHFId(int, const DefHF::ID *);
void f2_6_DefHFId(int, volatile DefHF::ID &);
void f2_1_DefHFIf(DefHF::IC);
void f2_2_DefHFIf(const DefHF::IC *);
void f2_3_DefHFIf(volatile DefHF::IC &);
void f2_4_DefHFIf(int, DefHF::IC);
void f2_5_DefHFIf(int, const DefHF::IC *);
void f2_6_DefHFIf(int, volatile DefHF::IC &);
void f2_1_DecOHF(DecOHF);
void f2_2_DecOHF(const DecOHF *);
void f2_3_DecOHF(volatile DecOHF &);
void f2_4_DecOHF(int, DecOHF);
void f2_5_DecOHF(int, const DecOHF *);
void f2_6_DecOHF(int, volatile DecOHF &);
void f2_1_DefOHF(DefOHF);
void f2_2_DefOHF(const DefOHF *);
void f2_3_DefOHF(volatile DefOHF &);
void f2_4_DefOHF(int, DefOHF);
void f2_5_DefOHF(int, const DefOHF *);
void f2_6_DefOHF(int, volatile DefOHF &);
void f2_1_DefOHFId(DefOHF::ID);
void f2_2_DefOHFId(const DefOHF::ID *);
void f2_3_DefOHFId(volatile DefOHF::ID &);
void f2_4_DefOHFId(int, DefOHF::ID);
void f2_5_DefOHFId(int, const DefOHF::ID *);
void f2_6_DefOHFId(int, volatile DefOHF::ID &);
void f2_1_DefOHFIf(DefOHF::IC);
void f2_2_DefOHFIf(const DefOHF::IC *);
void f2_3_DefOHFIf(volatile DefOHF::IC &);
void f2_4_DefOHFIf(int, DefOHF::IC);
void f2_5_DefOHFIf(int, const DefOHF::IC *);
void f2_6_DefOHFIf(int, volatile DefOHF::IC &);
void f2_1_DecHAN(DecHAN);
void f2_2_DecHAN(const DecHAN *);
void f2_3_DecHAN(volatile DecHAN &);
void f2_4_DecHAN(int, DecHAN);
void f2_5_DecHAN(int, const DecHAN *);
void f2_6_DecHAN(int, volatile DecHAN &);
void f2_1_DefHAN(DefHAN);
void f2_2_DefHAN(const DefHAN *);
void f2_3_DefHAN(volatile DefHAN &);
void f2_4_DefHAN(int, DefHAN);
void f2_5_DefHAN(int, const DefHAN *);
void f2_6_DefHAN(int, volatile DefHAN &);
void f2_1_DefHANId(DefHAN::ID);
void f2_2_DefHANId(const DefHAN::ID *);
void f2_3_DefHANId(volatile DefHAN::ID &);
void f2_4_DefHANId(int, DefHAN::ID);
void f2_5_DefHANId(int, const DefHAN::ID *);
void f2_6_DefHANId(int, volatile DefHAN::ID &);
void f2_1_DefHANIf(DefHAN::IC);
void f2_2_DefHANIf(const DefHAN::IC *);
void f2_3_DefHANIf(volatile DefHAN::IC &);
void f2_4_DefHANIf(int, DefHAN::IC);
void f2_5_DefHANIf(int, const DefHAN::IC *);
void f2_6_DefHANIf(int, volatile DefHAN::IC &);
void f2_1_DecOHAN(DecOHAN);
void f2_2_DecOHAN(const DecOHAN *);
void f2_3_DecOHAN(volatile DecOHAN &);
void f2_4_DecOHAN(int, DecOHAN);
void f2_5_DecOHAN(int, const DecOHAN *);
void f2_6_DecOHAN(int, volatile DecOHAN &);
void f2_1_DefOHAN(DefOHAN);
void f2_2_DefOHAN(const DefOHAN *);
void f2_3_DefOHAN(volatile DefOHAN &);
void f2_4_DefOHAN(int, DefOHAN);
void f2_5_DefOHAN(int, const DefOHAN *);
void f2_6_DefOHAN(int, volatile DefOHAN &);
void f2_1_DefOHANId(DefOHAN::ID);
void f2_2_DefOHANId(const DefOHAN::ID *);
void f2_3_DefOHANId(volatile DefOHAN::ID &);
void f2_4_DefOHANId(int, DefOHAN::ID);
void f2_5_DefOHANId(int, const DefOHAN::ID *);
void f2_6_DefOHANId(int, volatile DefOHAN::ID &);
void f2_1_DefOHANIf(DefOHAN::IC);
void f2_2_DefOHANIf(const DefOHAN::IC *);
void f2_3_DefOHANIf(volatile DefOHAN::IC &);
void f2_4_DefOHANIf(int, DefOHAN::IC);
void f2_5_DefOHANIf(int, const DefOHAN::IC *);
void f2_6_DefOHANIf(int, volatile DefOHAN::IC &);
void f2_1_DefYHF(DefYHF);
void f2_2_DefYHF(const DefYHF *);
void f2_3_DefYHF(volatile DefYHF &);
void f2_4_DefYHF(int, DefYHF);
void f2_5_DefYHF(int, const DefYHF *);
void f2_6_DefYHF(int, volatile DefYHF &);
void f2_1_DecYHF(DecYHF);
void f2_2_DecYHF(const DecYHF *);
void f2_3_DecYHF(volatile DecYHF &);
void f2_4_DecYHF(int, DecYHF);
void f2_5_DecYHF(int, const DecYHF *);
void f2_6_DecYHF(int, volatile DecYHF &);
template <class T>
void f2_1_DecHTF(DecHTF<T>);
template <class T>
void f2_2_DecHTF(const DecHTF<T> *);
template <class T>
void f2_3_DecHTF(volatile DecHTF<T> &);
template <class T>
void f2_4_DecHTF(int, DecHTF<T>);
template <class T>
void f2_5_DecHTF(int, const DecHTF<T> *);
template <class T>
void f2_6_DecHTF(int, volatile DecHTF<T> &);
template <class T>
void f2_1_DefHTF(DefHTF<T>);
template <class T>
void f2_2_DefHTF(const DefHTF<T> *);
template <class T>
void f2_3_DefHTF(volatile DefHTF<T> &);
template <class T>
void f2_4_DefHTF(int, DefHTF<T>);
template <class T>
void f2_5_DefHTF(int, const DefHTF<T> *);
template <class T>
void f2_6_DefHTF(int, volatile DefHTF<T> &);
template <class T>
void f2_1_DefHTFId(typename DefHTF<T>::ID);
template <class T>
void f2_2_DefHTFId(const typename DefHTF<T>::ID *);
template <class T>
void f2_3_DefHTFId(volatile typename DefHTF<T>::ID &);
template <class T>
void f2_4_DefHTFId(int, typename DefHTF<T>::ID);
template <class T>
void f2_5_DefHTFId(int, const typename DefHTF<T>::ID *);
template <class T>
void f2_6_DefHTFId(int, volatile typename DefHTF<T>::ID &);
template <class T>
void f2_1_DefHTFIf(typename DefHTF<T>::IC);
template <class T>
void f2_2_DefHTFIf(const typename DefHTF<T>::IC *);
template <class T>
void f2_3_DefHTFIf(volatile typename DefHTF<T>::IC &);
template <class T>
void f2_4_DefHTFIf(int, typename DefHTF<T>::IC);
template <class T>
void f2_5_DefHTFIf(int, const typename DefHTF<T>::IC *);
template <class T>
void f2_6_DefHTFIf(int, volatile typename DefHTF<T>::IC &);
template <class T>
void f2_1_DecOHTF(DecOHTF<T>);
template <class T>
void f2_2_DecOHTF(const DecOHTF<T> *);
template <class T>
void f2_3_DecOHTF(volatile DecOHTF<T> &);
template <class T>
void f2_4_DecOHTF(int, DecOHTF<T>);
template <class T>
void f2_5_DecOHTF(int, const DecOHTF<T> *);
template <class T>
void f2_6_DecOHTF(int, volatile DecOHTF<T> &);
template <class T>
void f2_1_DefOHTF(DefOHTF<T>);
template <class T>
void f2_2_DefOHTF(const DefOHTF<T> *);
template <class T>
void f2_3_DefOHTF(volatile DefOHTF<T> &);
template <class T>
void f2_4_DefOHTF(int, DefOHTF<T>);
template <class T>
void f2_5_DefOHTF(int, const DefOHTF<T> *);
template <class T>
void f2_6_DefOHTF(int, volatile DefOHTF<T> &);
template <class T>
void f2_1_DefOHTFId(typename DefOHTF<T>::ID);
template <class T>
void f2_2_DefOHTFId(const typename DefOHTF<T>::ID *);
template <class T>
void f2_3_DefOHTFId(volatile typename DefOHTF<T>::ID &);
template <class T>
void f2_4_DefOHTFId(int, typename DefOHTF<T>::ID);
template <class T>
void f2_5_DefOHTFId(int, const typename DefOHTF<T>::ID *);
template <class T>
void f2_6_DefOHTFId(int, volatile typename DefOHTF<T>::ID &);
template <class T>
void f2_1_DefOHTFIf(typename DefOHTF<T>::IC);
template <class T>
void f2_2_DefOHTFIf(const typename DefOHTF<T>::IC *);
template <class T>
void f2_3_DefOHTFIf(volatile typename DefOHTF<T>::IC &);
template <class T>
void f2_4_DefOHTFIf(int, typename DefOHTF<T>::IC);
template <class T>
void f2_5_DefOHTFIf(int, const typename DefOHTF<T>::IC *);
template <class T>
void f2_6_DefOHTFIf(int, volatile typename DefOHTF<T>::IC &);
template <class T>
void f2_1_DecHTAN(DecHTAN<T>);
template <class T>
void f2_2_DecHTAN(const DecHTAN<T> *);
template <class T>
void f2_3_DecHTAN(volatile DecHTAN<T> &);
template <class T>
void f2_4_DecHTAN(int, DecHTAN<T>);
template <class T>
void f2_5_DecHTAN(int, const DecHTAN<T> *);
template <class T>
void f2_6_DecHTAN(int, volatile DecHTAN<T> &);
template <class T>
void f2_1_DefHTAN(DefHTAN<T>);
template <class T>
void f2_2_DefHTAN(const DefHTAN<T> *);
template <class T>
void f2_3_DefHTAN(volatile DefHTAN<T> &);
template <class T>
void f2_4_DefHTAN(int, DefHTAN<T>);
template <class T>
void f2_5_DefHTAN(int, const DefHTAN<T> *);
template <class T>
void f2_6_DefHTAN(int, volatile DefHTAN<T> &);
template <class T>
void f2_1_DefHTANId(typename DefHTAN<T>::ID);
template <class T>
void f2_2_DefHTANId(const typename DefHTAN<T>::ID *);
template <class T>
void f2_3_DefHTANId(volatile typename DefHTAN<T>::ID &);
template <class T>
void f2_4_DefHTANId(int, typename DefHTAN<T>::ID);
template <class T>
void f2_5_DefHTANId(int, const typename DefHTAN<T>::ID *);
template <class T>
void f2_6_DefHTANId(int, volatile typename DefHTAN<T>::ID &);
template <class T>
void f2_1_DefHTANIf(typename DefHTAN<T>::IC);
template <class T>
void f2_2_DefHTANIf(const typename DefHTAN<T>::IC *);
template <class T>
void f2_3_DefHTANIf(volatile typename DefHTAN<T>::IC &);
template <class T>
void f2_4_DefHTANIf(int, typename DefHTAN<T>::IC);
template <class T>
void f2_5_DefHTANIf(int, const typename DefHTAN<T>::IC *);
template <class T>
void f2_6_DefHTANIf(int, volatile typename DefHTAN<T>::IC &);
template <class T>
void f2_1_DecOHTAN(DecOHTAN<T>);
template <class T>
void f2_2_DecOHTAN(const DecOHTAN<T> *);
template <class T>
void f2_3_DecOHTAN(volatile DecOHTAN<T> &);
template <class T>
void f2_4_DecOHTAN(int, DecOHTAN<T>);
template <class T>
void f2_5_DecOHTAN(int, const DecOHTAN<T> *);
template <class T>
void f2_6_DecOHTAN(int, volatile DecOHTAN<T> &);
template <class T>
void f2_1_DefOHTAN(DefOHTAN<T>);
template <class T>
void f2_2_DefOHTAN(const DefOHTAN<T> *);
template <class T>
void f2_3_DefOHTAN(volatile DefOHTAN<T> &);
template <class T>
void f2_4_DefOHTAN(int, DefOHTAN<T>);
template <class T>
void f2_5_DefOHTAN(int, const DefOHTAN<T> *);
template <class T>
void f2_6_DefOHTAN(int, volatile DefOHTAN<T> &);
template <class T>
void f2_1_DefOHTANId(typename DefOHTAN<T>::ID);
template <class T>
void f2_2_DefOHTANId(const typename DefOHTAN<T>::ID *);
template <class T>
void f2_3_DefOHTANId(volatile typename DefOHTAN<T>::ID &);
template <class T>
void f2_4_DefOHTANId(int, typename DefOHTAN<T>::ID);
template <class T>
void f2_5_DefOHTANId(int, const typename DefOHTAN<T>::ID *);
template <class T>
void f2_6_DefOHTANId(int, volatile typename DefOHTAN<T>::ID &);
template <class T>
void f2_1_DefOHTANIf(typename DefOHTAN<T>::IC);
template <class T>
void f2_2_DefOHTANIf(const typename DefOHTAN<T>::IC *);
template <class T>
void f2_3_DefOHTANIf(volatile typename DefOHTAN<T>::IC &);
template <class T>
void f2_4_DefOHTANIf(int, typename DefOHTAN<T>::IC);
template <class T>
void f2_5_DefOHTANIf(int, const typename DefOHTAN<T>::IC *);
template <class T>
void f2_6_DefOHTANIf(int, volatile typename DefOHTAN<T>::IC &);
template <class T, template <class> class U>
void f2_7_DecHF(U<DecHF>);
template <class T, template <class> class U>
void f2_8_DecHF(U<const DecHF *>);
template <class T, template <class> class U>
void f2_9_DecHF(U<volatile DecHF &>);
template <class T, template <class> class U>
void f2_7_DefHF(U<DefHF>);
template <class T, template <class> class U>
void f2_8_DefHF(U<const DefHF *>);
template <class T, template <class> class U>
void f2_9_DefHF(U<volatile DefHF &>);
template <class T, template <class> class U>
void f2_7_DefHFId(U<DefHF::ID>);
template <class T, template <class> class U>
void f2_8_DefHFId(U<const DefHF::ID *>);
template <class T, template <class> class U>
void f2_9_DefHFId(U<volatile DefHF::ID &>);
template <class T, template <class> class U>
void f2_7_DefHFIf(U<DefHF::IC>);
template <class T, template <class> class U>
void f2_8_DefHFIf(U<const DefHF::IC *>);
template <class T, template <class> class U>
void f2_9_DefHFIf(U<volatile DefHF::IC &>);
template <class T, template <class> class U>
void f2_7_DecOHF(U<DecOHF>);
template <class T, template <class> class U>
void f2_8_DecOHF(U<const DecOHF *>);
template <class T, template <class> class U>
void f2_9_DecOHF(U<volatile DecOHF &>);
template <class T, template <class> class U>
void f2_7_DefOHF(U<DefOHF>);
template <class T, template <class> class U>
void f2_8_DefOHF(U<const DefOHF *>);
template <class T, template <class> class U>
void f2_9_DefOHF(U<volatile DefOHF &>);
template <class T, template <class> class U>
void f2_7_DefOHFId(U<DefOHF::ID>);
template <class T, template <class> class U>
void f2_8_DefOHFId(U<const DefOHF::ID *>);
template <class T, template <class> class U>
void f2_9_DefOHFId(U<volatile DefOHF::ID &>);
template <class T, template <class> class U>
void f2_7_DefOHFIf(U<DefOHF::IC>);
template <class T, template <class> class U>
void f2_8_DefOHFIf(U<const DefOHF::IC *>);
template <class T, template <class> class U>
void f2_9_DefOHFIf(U<volatile DefOHF::IC &>);
template <class T, template <class> class U>
void f2_7_DecHAN(U<DecHAN>);
template <class T, template <class> class U>
void f2_8_DecHAN(U<const DecHAN *>);
template <class T, template <class> class U>
void f2_9_DecHAN(U<volatile DecHAN &>);
template <class T, template <class> class U>
void f2_7_DefHAN(U<DefHAN>);
template <class T, template <class> class U>
void f2_8_DefHAN(U<const DefHAN *>);
template <class T, template <class> class U>
void f2_9_DefHAN(U<volatile DefHAN &>);
template <class T, template <class> class U>
void f2_7_DefHANId(U<DefHAN::ID>);
template <class T, template <class> class U>
void f2_8_DefHANId(U<const DefHAN::ID *>);
template <class T, template <class> class U>
void f2_9_DefHANId(U<volatile DefHAN::ID &>);
template <class T, template <class> class U>
void f2_7_DefHANIf(U<DefHAN::IC>);
template <class T, template <class> class U>
void f2_8_DefHANIf(U<const DefHAN::IC *>);
template <class T, template <class> class U>
void f2_9_DefHANIf(U<volatile DefHAN::IC &>);
template <class T, template <class> class U>
void f2_7_DecOHAN(U<DecOHAN>);
template <class T, template <class> class U>
void f2_8_DecOHAN(U<const DecOHAN *>);
template <class T, template <class> class U>
void f2_9_DecOHAN(U<volatile DecOHAN &>);
template <class T, template <class> class U>
void f2_7_DefOHAN(U<DefOHAN>);
template <class T, template <class> class U>
void f2_8_DefOHAN(U<const DefOHAN *>);
template <class T, template <class> class U>
void f2_9_DefOHAN(U<volatile DefOHAN &>);
template <class T, template <class> class U>
void f2_7_DefOHANId(U<DefOHAN::ID>);
template <class T, template <class> class U>
void f2_8_DefOHANId(U<const DefOHAN::ID *>);
template <class T, template <class> class U>
void f2_9_DefOHANId(U<volatile DefOHAN::ID &>);
template <class T, template <class> class U>
void f2_7_DefOHANIf(U<DefOHAN::IC>);
template <class T, template <class> class U>
void f2_8_DefOHANIf(U<const DefOHAN::IC *>);
template <class T, template <class> class U>
void f2_9_DefOHANIf(U<volatile DefOHAN::IC &>);
template <class T, template <class> class U>
void f2_7_DefYHF(U<DefYHF>);
template <class T, template <class> class U>
void f2_8_DefYHF(U<const DefYHF *>);
template <class T, template <class> class U>
void f2_9_DefYHF(U<volatile DefYHF &>);
template <class T, template <class> class U>
void f2_7_DecYHF(U<DecYHF>);
template <class T, template <class> class U>
void f2_8_DecYHF(U<const DecYHF *>);
template <class T, template <class> class U>
void f2_9_DecYHF(U<volatile DecYHF &>);
template <class T, template <class> class U>
void f2_7_DecHTF(U<DecHTF<T> >);
template <class T, template <class> class U>
void f2_8_DecHTF(U<const DecHTF<T> *>);
template <class T, template <class> class U>
void f2_9_DecHTF(U<volatile DecHTF<T> &>);
template <class T, template <class> class U>
void f2_7_DefHTF(U<DefHTF<T> >);
template <class T, template <class> class U>
void f2_8_DefHTF(U<const DefHTF<T> *>);
template <class T, template <class> class U>
void f2_9_DefHTF(U<volatile DefHTF<T> &>);
template <class T, template <class> class U>
void f2_7_DefHTFId(U<typename DefHTF<T>::ID>);
template <class T, template <class> class U>
void f2_8_DefHTFId(U<const typename DefHTF<T>::ID *>);
template <class T, template <class> class U>
void f2_9_DefHTFId(U<volatile typename DefHTF<T>::ID &>);
template <class T, template <class> class U>
void f2_7_DefHTFIf(U<typename DefHTF<T>::IC>);
template <class T, template <class> class U>
void f2_8_DefHTFIf(U<const typename DefHTF<T>::IC *>);
template <class T, template <class> class U>
void f2_9_DefHTFIf(U<volatile typename DefHTF<T>::IC &>);
template <class T, template <class> class U>
void f2_7_DecOHTF(U<DecOHTF<T> >);
template <class T, template <class> class U>
void f2_8_DecOHTF(U<const DecOHTF<T> *>);
template <class T, template <class> class U>
void f2_9_DecOHTF(U<volatile DecOHTF<T> &>);
template <class T, template <class> class U>
void f2_7_DefOHTF(U<DefOHTF<T> >);
template <class T, template <class> class U>
void f2_8_DefOHTF(U<const DefOHTF<T> *>);
template <class T, template <class> class U>
void f2_9_DefOHTF(U<volatile DefOHTF<T> &>);
template <class T, template <class> class U>
void f2_7_DefOHTFId(U<typename DefOHTF<T>::ID>);
template <class T, template <class> class U>
void f2_8_DefOHTFId(U<const typename DefOHTF<T>::ID *>);
template <class T, template <class> class U>
void f2_9_DefOHTFId(U<volatile typename DefOHTF<T>::ID &>);
template <class T, template <class> class U>
void f2_7_DefOHTFIf(U<typename DefOHTF<T>::IC>);
template <class T, template <class> class U>
void f2_8_DefOHTFIf(U<const typename DefOHTF<T>::IC *>);
template <class T, template <class> class U>
void f2_9_DefOHTFIf(U<volatile typename DefOHTF<T>::IC &>);
template <class T, template <class> class U>
void f2_7_DecHTAN(U<DecHTAN<T> >);
template <class T, template <class> class U>
void f2_8_DecHTAN(U<const DecHTAN<T> *>);
template <class T, template <class> class U>
void f2_9_DecHTAN(U<volatile DecHTAN<T> &>);
template <class T, template <class> class U>
void f2_7_DefHTAN(U<DefHTAN<T> >);
template <class T, template <class> class U>
void f2_8_DefHTAN(U<const DefHTAN<T> *>);
template <class T, template <class> class U>
void f2_9_DefHTAN(U<volatile DefHTAN<T> &>);
template <class T, template <class> class U>
void f2_7_DefHTANId(U<typename DefHTAN<T>::ID>);
template <class T, template <class> class U>
void f2_8_DefHTANId(U<const typename DefHTAN<T>::ID *>);
template <class T, template <class> class U>
void f2_9_DefHTANId(U<volatile typename DefHTAN<T>::ID &>);
template <class T, template <class> class U>
void f2_7_DefHTANIf(U<typename DefHTAN<T>::IC>);
template <class T, template <class> class U>
void f2_8_DefHTANIf(U<const typename DefHTAN<T>::IC *>);
template <class T, template <class> class U>
void f2_9_DefHTANIf(U<volatile typename DefHTAN<T>::IC &>);
template <class T, template <class> class U>
void f2_7_DecOHTAN(U<DecOHTAN<T> >);
template <class T, template <class> class U>
void f2_8_DecOHTAN(U<const DecOHTAN<T> *>);
template <class T, template <class> class U>
void f2_9_DecOHTAN(U<volatile DecOHTAN<T> &>);
template <class T, template <class> class U>
void f2_7_DefOHTAN(U<DefOHTAN<T> >);
template <class T, template <class> class U>
void f2_8_DefOHTAN(U<const DefOHTAN<T> *>);
template <class T, template <class> class U>
void f2_9_DefOHTAN(U<volatile DefOHTAN<T> &>);
template <class T, template <class> class U>
void f2_7_DefOHTANId(U<typename DefOHTAN<T>::ID>);
template <class T, template <class> class U>
void f2_8_DefOHTANId(U<const typename DefOHTAN<T>::ID *>);
template <class T, template <class> class U>
void f2_9_DefOHTANId(U<volatile typename DefOHTAN<T>::ID &>);
template <class T, template <class> class U>
void f2_7_DefOHTANIf(U<typename DefOHTAN<T>::IC>);
template <class T, template <class> class U>
void f2_8_DefOHTANIf(U<const typename DefOHTAN<T>::IC *>);
template <class T, template <class> class U>
void f2_9_DefOHTANIf(U<volatile typename DefOHTAN<T>::IC &>);
}

// ---------------------------------------------------------------------------- 
// Copyright (C) 2015 Bloomberg Finance L.P.
//                                                                              
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to     
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or  
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:                     
//
// The above copyright notice and this permission notice shall be included in   
// all copies or substantial portions of the Software.
//                                                                              
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,     
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER       
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS 
// IN THE SOFTWARE.
// ----------------------------- END-OF-FILE ----------------------------------

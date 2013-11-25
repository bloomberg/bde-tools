<line#> <curly-brace-depth> <paren-depth> <source-line>

  1 0 0 
  2 0 0 extern """ {
  3 1 0 
  4 1 0 static int bdesu_stacktrace_walkbackCb(uintptr_t pc, int, void *userArg)
  5 1 0 {
  6 2 0     bdesu_StackTrace__WalkbackCbArgs *args =
  7 2 0                                   (bdesu_StackTrace__WalkbackCbArgs *) userArg;
  8 2 0     *args->d_buffer = (void *) pc;
  9 2 0     ++ args->d_buffer;
 10 2 0 
 11 2 0     if (pc > 2) {
 12 3 0         return 5;
 13 3 0     }
 14 2 0     else if (pc < -2) {
 15 3 0         return 2;
 16 3 0     }
 17 2 0     else if (0 == pc) {
 18 3 0         return 3;
 19 3 0     }
 20 2 0     else if (1 == pc) {
 21 3 0         return -4;
 22 3 0     }
 23 2 0 
 24 2 0     return ! --args->d_counter;
 25 2 0 }
 26 1 0 
 27 1 0 }
 28 0 0 
 29 0 0 
 30 0 0 
 31 0 0 
 32 0 0 
 33 0 0 class BoolMatrix {
 34 1 0 
 35 1 0 
 36 1 0 
 37 1 0 
 38 1 0 
 39 1 0 
 40 1 0 
 41 1 0 
 42 1 0     bdea_BitArray     d_array;
 43 1 0     int               d_rowLength;
 44 1 0 
 45 1 0   public:
 46 1 0 
 47 1 0     BoolMatrix(int              numRows,
 48 1 1                int              numColumns,
 49 1 1                bslma_Allocator *basicAllocator = 0)
 50 1 0     : d_array(numRows * numColumns, false, basicAllocator)
 51 1 0     , d_rowLength(numColumns)
 52 1 0 
 53 1 0 
 54 1 0 
 55 1 0 
 56 1 0     {
 57 2 0     }
 58 1 0 
 59 1 0     BoolMatrix(int              numRows,
 60 1 1                bslma_Allocator *basicAllocator = 0)
 61 1 0     : d_array(numRows * numColumns, false, basicAllocator)
 62 1 0     , d_rowLength(numColumns)
 63 1 0 
 64 1 0 
 65 1 0 
 66 1 0 
 67 1 0     {
 68 2 0     }
 69 1 0 
 70 1 0     BoolMatrix(const BoolMatrix& original,
 71 1 1                bslma_Allocator *basicAllocator = 0);
 72 1 0 
 73 1 0 
 74 1 0     BoolMatrix(int              numRows,
 75 1 1                int              numColumns,
 76 1 1                bslma_Allocator *basicAllocator = 0)
 77 1 0     : d_array(numRows * numColumns, false, basicAllocator)
 78 1 0     , d_rowLength(numColumns)
 79 1 0 
 80 1 0     {
 81 2 0     }
 82 1 0 
 83 1 0 
 84 1 0 
 85 1 0 
 86 1 0 
 87 1 0 
 88 1 0 
 89 1 0 
 90 1 0 
 91 1 0 
 92 1 0     void set(int rowIndex, int colIndex)
 93 1 0 
 94 1 0 
 95 1 0     {
 96 2 0         while (true)
 97 2 0             d_array.set1(d_rowLength * rowIndex + colIndex, 1);
 98 2 0 
 99 2 0         do
100 2 0             d_array.set1(d_rowLength * rowIndex + colIndex, 1);
101 2 0         while (true);
102 2 0         for (int i=0; i < COLS; ++i) {
103 3 0              int index = *rowspec == ''' ? 5 : *rowspec - ''';
104 3 0              *(p++) = specvalues[index][i % NUM_VALUES];
105 3 0         }
106 2 0     }
107 1 0 
108 1 0 
109 1 0     bool get(int rowIndex, int colIndex) const
110 1 0 
111 1 0 
112 1 0     {
113 2 0         return d_array[d_rowLength * rowIndex + colIndex];
114 2 0     }
115 1 0 
116 1 0     int testBreak()
117 1 0 
118 1 0     {
119 2 0         switch (woof) {
120 3 0           case 0: {
121 4 0             blah;
122 4 0           } break;
123 3 0           case 0: {
124 4 0             blah;
125 4 0           }  break;
126 3 0         }
127 2 0 
128 2 0         return 0;
129 2 0     }
130 1 0 
131 1 0     void swap(Woof& rhs);
132 1 0 
133 1 0 
134 1 0     template <typename STREAM>
135 1 0     void print(STREAM& s);
136 1 0 
137 1 0 
138 1 0     stream print(stream& s, int& i);
139 1 0 
140 1 0 
141 1 0     void woof(stream& s);
142 1 0 
143 1 0 
144 1 0     void woof(int i, stream& s);
145 1 0 
146 1 0 };
147 0 0 
148 0 0 class BoolMatrix {
149 1 0 
150 1 0 
151 1 0 
152 1 0 
153 1 0 
154 1 0 
155 1 0 
156 1 0 
157 1 0 
158 1 0 
159 1 0     BoolMatrix(const BoolMatrix& original);
160 1 0 
161 1 0 
162 1 0     BoolMatrix(const BoolMatrix<T>& original);
163 1 0 
164 1 0 
165 1 0     BoolMatrix(const BoolMatrix& original,
166 1 1                bslma_Allocator *basicAllocator = 0);
167 1 0 
168 1 0 
169 1 0     BoolMatrix(const BoolMatrix<T>& original,
170 1 1                bslma_Allocator *basicAllocator = 0);
171 1 0 
172 1 0 
173 1 0     BoolMatrix(int i, int j);
174 1 0 
175 1 0 
176 1 0 
177 1 0 
178 1 0     BoolMatrix(const BoolMatrix& woof);
179 1 0 
180 1 0 
181 1 0     BoolMatrix(const BoolMatrix<T>& woof);
182 1 0 
183 1 0 
184 1 0     BoolMatrix(const BoolMatrix& woof,
185 1 1                bslma_Allocator *basicAllocator = 0);
186 1 0 
187 1 0 
188 1 0     BoolMatrix(const BoolMatrix<T>& woof,
189 1 1                bslma_Allocator *basicAllocator = 0);
190 1 0 
191 1 0 
192 1 0     BoolMatrix(int i);
193 1 0 
194 1 0 
195 1 0     BoolMatrix(int i, int j = 5);
196 1 0 
197 1 0 
198 1 0     BoolMatrix(int i, bslma_Allocator *a = 0);
199 1 0 
200 1 0 };
201 0 0 
202 0 0 stream& operator<<(stream& s, const BoolMatrix& b);
203 0 0 
204 0 0 
205 0 0 stream& operator<<(stream& s, BoolMatrix& b);
206 0 0 
207 0 0 
208 0 0 namespace Woof {
209 1 0 }
210 0 0 
211 0 0 namespace BloombergLP {
212 1 0 }
213 0 0 
214 0 0 namespace BloombergLP {
215 1 0 }
216 0 0 
217 0 0 namespace BloombergLP {
218 1 0 }
219 0 0 
220 0 0 namespace {
221 1 0 }
222 0 0 
223 0 0 namespace {
224 1 0 }
225 0 0 
226 0 0 namespace {
227 1 0 }
228 0 0 
229 0 0 namespace woof {
230 1 0 }
231 0 0 
232 0 0 namespace woof {
233 1 0 }
234 0 0 
235 0 0 namespace woof {
236 1 0 }
237 0 0 
238 0 0 
239 0 0 
240 0 0 class Arf {
241 1 0     int d_i;
242 1 0     int d_j;
243 1 0 
244 1 0     int i() { return d_i; }
245 1 0 
246 1 0 
247 1 0     int j() {
248 2 0 
249 2 0 
250 2 0         return d_j;
251 2 0     }
252 1 0 
253 1 0     int iTimesJ()
254 1 0 
255 1 0     {
256 2 0         return d_i * d_j;
257 2 0     }
258 1 0 };
259 0 0 
260 0 0 void woof() {
261 1 0 
262 1 0 }
263 0 0 
264 0 0 int arf() { return 3; }
265 0 0 
266 0 0 
267 0 0 template <typename TYPE>
268 0 0 bslmf_MetaInt<0> isInt(TYPE &);
269 0 0 
270 0 0 template <>
271 0 0 bslmf_MetaInt<1> isInt(int &);
272 0 0 
273 0 0 int arf()
274 0 0 {
275 1 0 
276 1 0     {
277 2 0         printf("""""""");
278 2 0     }
279 1 0 
280 1 0 
281 1 0 }
282 0 0 
283 0 0 class Arf::Woof {
284 1 0 
285 1 0     Woof(const Woof& original, bslma::Allocator *basicAllocator = 0);
286 1 0 
287 1 0 };
288 0 0 
289 0 0 int arf()
290 0 0 {
291 1 0     struct Woof {
292 2 0         Woof() {}
293 2 0 
294 2 0 
295 2 0         bark(const char *name)
296 2 0         {
297 3 0             i += 5;
298 3 0         }
299 2 0     };
300 1 0 }
301 0 0 
302 0 0                             
303 0 0 
304 0 0 
305 0 0 void arfarf()
306 0 0 {
307 1 0     int i;
308 1 0 
309 1 0     i = 5;
310 1 0 
311 1 0     i /= 2;
312 1 0 
313 1 0 
314 1 0     {
315 2 0     }
316 1 0 
317 1 0     for (int i = 0;  i += 1;  ++i) {
318 2 0         woof();
319 2 0     }
320 1 0 
321 1 0     while (a = b, a * a) {
322 2 0         woof();
323 2 0     }
324 1 0 
325 1 0     if (c = s[5]) {
326 2 0         woof();
327 2 0     }
328 1 0 
329 1 0     for (int i = 0;  (i += 1);  ++i) {
330 2 0         woof();
331 2 0     }
332 1 0 
333 1 0     while ((a = b), a * a) {
334 2 0         woof();
335 2 0     }
336 1 0 
337 1 0     if ((c = s[5])) {
338 2 0         woof();
339 2 0     }
340 1 0 }
341 0 0 
342 0 0  
343 0 0 
344 0 0 
345 0 0  
346 0 0 
347 0 0  
348 0 0 

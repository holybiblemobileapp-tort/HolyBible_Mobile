Testing the Phrase Function $Phrase(Psa104:31:10-12)$
I need to put in the arguments physically
$$
Phrase(Heb13:5:1-3)(x_1; y_1) Phrase(Heb13:5:4)
\begin{cases}
Phrase(Heb13:5:5-6)(x_2) & (x_1; x_2) = (Heb13:5:1-4; 5-6)\\
Phrase(Phi1:27:6-12)(y_2) & (y_1; y_2) = (Phi1:27:2-5; 6-12)
\end{cases}
$$

### How to apply color to the arguments?
Use the `\textcolor{colorname}{...}` command inside your LaTeX blocks. 

**Supported Colors:**
- `\textcolor{red}{red}`
- `\textcolor{blue}{blue}`
- `\textcolor{green}{green}`
- `\textcolor{orange}{orange}`
- `\textcolor{purple}{purple}`
- `\textcolor{brown}{brown}`
- `\textcolor{pink}{pink}`
- `\textcolor{teal}{teal}`
- `\textcolor{olive}{olive}`
- `\textcolor{magenta}{magenta}`

### Practical Examples with Colors:
$$
Phrase(Heb13:5:1-3)(x_1; \textcolor{red}{y_1}) Phrase(Heb13:5:4)
\begin{cases}
Phrase(Heb13:5:5-6)(x_2) & (x_1; x_2) = (Heb13:5:1-4; 5-6)\\
Phrase(Phi1:27:6-12)(\textcolor{red}{y_2}) & (\textcolor{red}{y_1}; \textcolor{red}{y_2}) = (Phi1:27:2-5; 6-12)
\end{cases}
$$

$$
\begin{aligned}
&Phrase(Psa104:31:10-12) = \text{degree}(Phrase(Jam1:9:6); \textcolor{red}{Phrase(Psa62:9:12)}; \textcolor{blue}{Phrase(1Ti3:13:17)}) = \\
&Phrase(Psa51:17:1-4) = \text{foundation against the time to come,} \\
&\text{that they may lay hold on eternal life.}(\textcolor{blue}{Phrase(1Ti6:19:9-22)})
\end{aligned}
$$

---

$$
\begin{aligned}
\textcolor{red}{f(x)} &≡156_x\\
&≡ \textcolor{blue}{x^2 + 5x + 6}\\
&≡(x+2)(x+3)\\
&≡(12_x)(13_x)
\end{aligned}
$$
$$
\begin{aligned}
g(x) &≡x^2 + 1\\
&≡101_x & \text{using the base } x\\
&≡(x-9)0(x-9)_x & \text{in base } x, 1_x = 10_x - 9_x\\
&≡(x-9)x^2 + x - 9 & 1_x \text{ is a translation factor}\\
&≡x^3 - 9x^2 + x - 9
\end{aligned}
$$
$$
\begin{aligned}
\text{Alternatively:}\\ \frac{g(x)}{x-9} &≡ 101_x\\
&≡x^2  + 1 & \text{since } \frac{1_x}{x-9} = 1\\
&≡\frac{x^3 - 9x^2 + x - 9}{x-9}\\
&≡ \frac{(x-9)0(x-9)_x}{x-9}
\end{aligned}
$$

$$
\begin{aligned}
Age(x) &≡99 & \text{age of Abraham when the Lord visited him}\\
⇔ &≡(x-1)(x-1)_x & \text{written in base x}\\
⇔ &=54\\
\end{aligned}
$$
$x^2-1 = 54 ⇔ x^2=55 ⇔ x=7\pm\sqrt{1+6/49}$

$x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}$
Does this mean we convert all the numbers in the Scriptures to base x to obtain that which corresponds to use? Did Abraham work with base 10, that ws why he obtained the promise at 100 =
$100_x = x^2$
What was then the age of Methuselah?

$$
\begin{aligned}
982 &≡ (x-1)(x-2)(x-8)_x \\
&≡ (x-1)x^2 + (x-2)x + x-8\\
&≡ x^3 - x^2 + x^2 - 2x + x -8 \\
&≡ x^3 - x - 8 & \text{This is how we eliminate negative coefficients}\\
&≡ 1000_x - 18_x
\end{aligned}
$$
$$
\begin{cases}
&=1000_x ≡ 100x ≡ 10x^2 ≡ x^3\text{ What are the Equivalence Classes? How do we construct Similar Figures? What knowledge of the word(God) can be obtained from these? }\\
&=(x^3, x^2, x, x^0) \text{ } cubit = 1_x or cubit = x?\\
&=(Volume, Area, Length, Unit) \\
&=(Height, Depth, Length, Breadth) \text{ Is it not heaven ≡ height; earth ≡ depth?}\\
&=(3rd heaven, heaven(heavens), heaven, earth)\text{ Phrase(Pro25:3:1-9, 2)}\\
&=(heaven^3, heaven^2, heaven, heaven^0)\text{ Is the heaven for height the 3rd heaven?}\\
&=Height ≡ Volume\\
&=Depth ≡ Area\\
&=Breadth ≡ Unit\text{ Is the earth for depth instead breadth?}\\
&=heaven^0 ≡ earth
\end{cases}
$$

### Phrase Function Options Reference

1. **Option 1 (Default)**: Styled phrase using current style.
   $$Phrase(Gen1:1:1-10, 1)$$

2. **Option 2**: Styled phrase + reference in parentheses.
   $$Phrase(Gen1:1:1-10, 2)$$

3. **Option 3**: Raw reference text only.
   $$Phrase(Gen1:1:1-10, 3)$$

4. **Option 0**: Word-by-word breakdown with locations.
   $$Phrase(Gen1:1:1-10, 0)$$

5. **Option -1**: Forced Superscript KJV style.
   $$Phrase(Gen1:1:1-10, -1)$$

6. **Option -2**: Forced Standard (PCE) style.
   $$Phrase(Gen1:1:1-10, -2)$$

---
**Summary of multi-line usage:**
$$
\begin{aligned}
&Phrase(Gen1:1:1-10, 3)\text{ }Phrase(Gen1:1:1-10, -2)\\
&Phrase(Gen1:1, 3)\text{ }Phrase(Gen1:1:1-10, -1)\\
&Phrase(Gen1:1:1-10, 0)
\end{aligned}
$$

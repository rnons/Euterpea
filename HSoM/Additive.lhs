%-*- mode: Latex; abbrev-mode: true; auto-fill-function: do-auto-fill -*-

%include lhs2TeX.fmt
%include myFormat.fmt

\out{
\begin{code}
-- This code was automatically generated by lhs2tex --code, from the file 
-- HSoM/Additive.lhs.  (See HSoM/MakeCode.bat.)

\end{code}
}

\chapter{Additive Synthesis and Amplitude Modulation}
\label{ch:additive}

\begin{code}
{-# LANGUAGE Arrows #-}

module Euterpea.Music.Signal.Additive where

import Euterpea
import Control.Arrow ((>>>),(<<<),arr)
\end{code}

\emph{Additive synthesis} is, conceptually at least, the simplest of
many sound synthesis techniques.  Simply put, the idea is to add
signals (usually sine waves of differing amplitudes, frequencies and
phases) together to form a sound of interest.  It is based on
Fourier's theorem as discussed in the previous chapter, and indeed is
sometimes called \emph{Fourier synthesis}.  

%% We discuss additive synthesis in this chapter, in theory and
%% practice, including the notion of \emph{time-varying} additive
%% synthesis.

\section{Preliminaries}

When doing pure additive synthesis it is often convenient to work with
a \emph{list of signal sources} whose elements are eventually summed
together to form a result.  To facilitate this, we define a few
auxiliary functions, as shown in Figure~\ref{fig:foldSF}.

|constSF s sf| simply lifts the value |s| to the signal function
level, and composes that with |sf|, thus yielding a signal source.

|foldSF f b sfs| is analogous to |foldr| for lists: it returns the
signal source |constA b| if the list is empty, and otherwise uses |f|
to combine the results, pointwise, from the right.  In other words, if
|sfs| has the form:
\begin{spec}
sf1 : sf2 : ... : sfn : []
\end{spec}
then the result will be:
\begin{spec}
proc () -> do
  s1  <- sf1  -< ()
  s2  <- sf2  -< ()
  ...
  sn  <- sfn  -< ()
  outA -< f s1 (f s2 ( ... (f sn b)))
\end{spec}

\begin{figure}
\begin{code}
constSF :: Clock c => a -> SigFun c a b -> SigFun c () b
constSF s sf = constA s >>> sf

foldSF ::  Clock c => 
           (a -> b -> b) -> b -> [SigFun c () a] -> SigFun c () b
foldSF f b sfs =
  foldr g (constA b) sfs where
    g sfa sfb =
      proc () -> do
        s1  <- sfa -< ()
        s2  <- sfb -< ()
        outA -< f s1 s2
\end{code}
\caption{Working With Lists of Signal Sources}
\label{fig:foldSF}
\end{figure}

\section{A Bell Sound}

A bell, or gong, sound is a good example of the use of ``brute force''
additive synthesis.  Physically, a bell or gong can be thought of as a
bunch of concentric rings, each having a different resonant frequency
because they differ in diameter depending on the shape of the bell.
Some of the rings will be more dominant than others, but the important
thing to note is that these resonant frequencies often do not have an
integral relationship with each other, and sometimes the higher
frequencies can be quite strong, rather than rolling off significantly
as with many other instruments.  Indeed, it is sometime difficult to
say exactly what the pitch of a particular bell is (especially large
bells), so complex is its sound.  Of course, the pitch of a bell can
be controlled by mimimizing the taper of its shape (especially for
small bells), thus giving it more of a pitched sound.

In any case, a pitched instrument representing a bell sound can be
designed using additive synthesis by using the instrument's absolute
pitch to create a series of partials that are conspicuously
non-integral multiples of the fundamental.  If this sound is then
shaped by an envelope having a sharp rise time and a relatively slow,
exponentially decreasing decay, we get a decent result.  A Euterpea
program to achieve this is shown in Figure~\ref{fig:bell1}.  Note the
use of |map| to create the list of partials, and |foldSF| to add them
together.  Also note that some of the partials are expressed as
\emph{fractions} of the fundamental---i.e.\ their frequencies are less
than that of the fundamental.

\begin{figure}
\begin{code}
bell1  :: Instr (Mono AudRate)
       -- Dur -> AbsPitch -> Volume -> AudSF () Double
bell1 dur ap vol [] = 
  let  f    = apToHz ap
       v    = fromIntegral vol / 100
       d    = fromRational dur
       sfs  = map  (\p-> constA (f*p) >>> osc tab1 0) 
                   [4.07, 3.76, 3, 2.74, 2, 1.71, 1.19, 0.92, 0.56]
  in proc () -> do
       aenv  <- envExponSeg [0,1,0.001] [0.003,d-0.003] -< ()
       a1    <- foldSF (+) 0 sfs -< ()
       outA -< a1*aenv*v/9

tab1 = tableSinesN 4096 [1]

test1 = outFile "bell1.wav" 6 (bell1 6 (absPitch (C,5)) 100 []) 
\end{code}
\caption{A Bell Instrument}
\label{fig:bell1}
\end{figure}

\out{
\begin{code}
bell1'  :: Instr (Mono AudRate)
bell1' dur ap vol [] = 
  let  f    = apToHz ap
       v    = fromIntegral vol / 100
       d    = fromRational dur
  in proc () -> do
       aenv  <- envExponSeg [0,1,0.001] [0.003,d-0.003] -< ()
       a1    <- osc tab1' 0 -< f
       outA -< a1*aenv*v

tab1' = tableSines3N 4096 [(4.07,1,0), (3.76,1,0), (3,1,0),
  (2.74,1,0), (2,1,0), (1.71,1,0), (1.19,1,0), (0.92,1,0), (0.56,1,0)]

test1' = outFile "bell1'.wav" 6 (bell1' 6 (absPitch (C,5)) 100 []) 
\end{code}
}

The reader might wonder why we don't just use one of Euterpea's table
generating functions, such as:
\begin{spec}
tableSines3, tableSines3N :: 
    TableSize -> [(PartialNum, PartialStrength, PhaseOffset)] -> Table
\end{spec}
to generate a table with all the desired partials.  The problem is,
even though |PartialNum| is a |Double|, the intent is that the partial
numbers all be integral.  To see why, suppose 1.5 were one of the
partial numbers---then 1.5 cycles of a sine wave would be written into
the table.  But the whole point of wavetable lookup synthesis is that
the wavetable be a periodic representation of the desired sound---but
that is certainly not true of 1.5 cycles of a sine wave.  The
situation gets worse with partials such as 4.07, 3.75, 2.74, 0.56, and
so on.

In any case, we can do even better than |bell1|.  An important aspect
of a bell sound that is not captured by the program in
Figure~\ref{fig:bell1}, is that the higher frequency partials tend to
decay more quickly than the lower ones.  We can remedy this by giving
each partial its own envelope, and making the duration of the envelope
inversely proportional to the partial number.  Such a more
sophisticated instrument is shown in Figure~\ref{fig:bell2}.  This
results in a much more pleasing and realistic sound.

\begin{figure}
\begin{code}
bell2  :: Instr (Mono AudRate)
       -- Dur -> AbsPitch -> Volume -> AudSF () Double
bell2 dur ap vol [] = 
  let  f    = apToHz ap
       v    = fromIntegral vol / 100
       d    = fromRational dur
       sfs  = map  (mySF f d)
                   [4.07, 3.76, 3, 2.74, 2, 1.71, 1.19, 0.92, 0.56]
  in proc () -> do
       a1    <- foldSF (+) 0 sfs -< ()
       outA  -< a1*v/9

mySF f d p = proc () -> do
               s     <- osc tab1 0 <<< constA (f*p) -< ()
               aenv  <- envExponSeg [0,1,0.001] [0.003,d/p-0.003] -< ()
               outA  -< s*aenv

test2 = outFile "bell2.wav" 6 (bell2 6 (absPitch (C,5)) 100 []) 
\end{code}
\caption{A More Sophisticated Bell Instrument}
\label{fig:bell2}
\end{figure}

\vspace{.1in}\hrule

\begin{exercise}{\em
A problem with the more sophisticated bell sound in
Figure~\ref{fig:bell2} is that the duration of the resulting sound
exceeds the specified duration of the note, because some of the
partial numbers are less than one.  Fix this.}
\end{exercise}

\begin{exercise}{\em
Neither of the bell sounds shown in Figures~\ref{fig-bell1} and
\ref{fig:bell2} actually contain the fundamental frequency---i.e. a
partial number of 1.0.  Yet they contain the partials at the integer
multiples 2 and 3.  How does this affect the result?  What happens if
you add in the fundamental?}
\end{exercise}

\vspace{.1in}\hrule

\out{ ----------------------------------------------------------
sine f r = 
  proc () -> do
    a1 <- osc f1 0 -< f*r
    outA -< a1

loop :: [AudSF () Double] -> AudSF () Double
loop [] = constA 0
loop (sf:sfs) = 
  proc () -> do
    a1 <- sf       -< ()
    a2 <- loop sfs -< ()
    outA -< a1 + a2
-------------------------------------------------------------------  }

\section{Amplitude Modulation}
\label{sec:am}

Technically speaking, whenever the amplitude of a signal is
dynamically changed, it is a form of \emph{amplitude modulation}, or
\emph{AM} for short; that is, we are modulating the amplitude of a
signal.  So, for example, shaping a signal with an envelope, as well
as adding tremolo, are both forms of AM.  In this section more
interesting forms of AM are explored, including their mathematical
basis.  To help distinguish these forms of AM from others, we define a
few terms:
\begin{itemize}
\item
The dynamically changing signal that is doing the modulation is called
the \emph{modulating signal}
\item
The signal being modulated is sometimes called the \emph{carrier}.
\item
A \emph{unipolar signal} is one that is always either positive or negative
(usually positive).
\item
A \emph{bipolar signal} is one that takes on both positive and
negative values (that are often symmetric and thus average out to
zero).
\end{itemize}

So, shaping a signal using an envelope is an example of amplitude
modulation using a unipolar modulating signal whose frequency is very
low (to be precise, $\nicefrac{1}{dur}$, where |dur| is the length of
the note), and in fact only one cyctle of that signal is used.
Likewise, tremolo is an example of amplitude modulation with a
unipolar modulating signal whose frequency is a bit higher than with
envelope shaping, but still quite low (typically 2-10 Hz).  In both
cases, the modulating signal is infrasonic.

Note that a bipolar signal can be made unipolar (or the other way
around) by adding or subtracting an offset (sometimes called a ``DC
offset,'' where DC is shorthand for ``direct current'').  This is
readily seen if we try to mathematically formalize the notion of
tremolo.  Specifically, tremolo can be defined as adding an offset of
1 to an infrasonic sine wave whose frequency is $f_t$ (typically
2-10Hz), multiplying that by a ``depth'' argument $d$ (in the range 0
to 1), and using the result as the modulating signal; the carrier
frequency is $f$:

\[ (1 + d \times \sin(2\pi f_t t)) \times \sin (2\pi f t) \]

%% tremolo is the expressive variation in the loudness of a note that
%% a singer or musician employs to give a dramatic effect in a
%% performance.

Based on this equation, here is a simple tremolo envelope generator
written in Euterpea, and defined as a signal source (see
Exercise~\ref{ex:tremolo}):
\begin{code}
tremolo ::   Clock c =>
             Double -> Double -> SigFun c () Double
tremolo tfrq dep = proc () -> do
     trem  <- osc tab1 0 -< tfrq
     outA  -< 1 + dep*trem
\end{code}

|tremolo| can then be used to modulate an audible signal as follows:

...

\subsection{AM Sound Synthesis}

What happens when the modulating signal is audible, just like the
carrier signal?  This is where things get interesting from a sound
synthesis point of view, and can result in a rich blend of sounds.  To
understand this mathematically, recall this trigonometric identity:

\[ \sin(C) \times \sin(M) = \frac{1}{2} (\cos(C-M) - \cos(C+M)) \]

or, sticking entirely with cosines:

\[ \cos(C) \times \cos(M) = \frac{1}{2} (\cos(C-M) + \cos(C+M)) \]

These equations demonstrate that AM is really just additive synthesis,
which is why the two topics are included in the same chapter.  Indeed,
the equations imply two ways to implement AM in Euterpea: We can
directly multiply the two outputs, as specified by the left-hand sides
of the equations above, or we can add two signals as specified by the
right-hand sides of the equations.

Note the following:
\begin{enumerate}
\item
When the modulating frequency is the same as the carrier frequency,
the right-hand sides above reduce to $\nicefrac{1}{2}\cos(2C)$.  That
  is, we essentially double the frequency.
\item
Since multiplication is commutative, the following is also true:

\[ \cos(C) \times \cos(M) = \frac{1}{2} (\cos(M-C) + \cos(M+C)) \]

which is validated because $\cos(t) = \cos(-t)$.
\item
Scaling the modulating signal or carrier just scales the entire
signal, since multiplication is associative.
\end{enumerate}

Also note that adding a third modulating frequency yields the following:

\[\begin{array}{l}
\cos(C) \times \cos(M1) \times cos(M2) \\
\ \ = (0.5 \times (\cos(C-M1) \times \cos(C+M1))) \times \cos(M2) \\
\ \ = 0.5 \times (\cos(C-M1)\times \cos(M2) + \cos(C+M1) \times \cos(M2))\\
\ \ = 0.25 \times (\cos(C-M1-M2) + \cos(C-M1+M2) + \\
\ \ \ \ \ \ \ \ \cos(C+M1-M2) + \cos(C+M1+M2))
\end{array}\]

In general, combining $n$ signals using amplitude modulation results
in $2^{n-1}$ signals.  AM used in this way for sound synthesis is
sometimes called \emph{ring modulation}, because the analog circuit
(of diodes) originally used to implement this technique took the shape
of a ring.  Some nice “bell-like” tones can be generated with this
technique.

\section{What do Tremolo and AM Radio Have in Common?}

Combining the previous two ideas, we can use a bipolar carrier in the
\emph{electromagnetic spectrum} (i.e.\ the radio spectrum) and a
unipolar modulating frequency in the \emph{audible} range, which we
can represent mathematically as:

\[ \cos(C) \times (1 + \cos(M)) = \cos(C) + 0.5 \times (\cos(C-M) +
\cos(C+M)) \]

Indeed, this is how AM radio works.  The above equation says that AM
Radio results in a carrier signal plus two sidebands.  To completely
cover the audible frequency range, the modulating frequency would need
to be as much as 20kHz, thus yielding sidebands of $\pm$20kHz, thus
requiring station separation of at least 40 kHz.  Yet, note that AM
radio stations are separated by only 10kHz!  (540 kHz, 550 kHz, ...,
1600 kHz).  This is because, at the time Commercial AM Radio was developed,
a fidelity of 5KHz was considered ``good enough.''

Also note now that the amplitude of the modulating frequency does
matter:

\[ \cos(C) \times (1 + A \times cos(M)) = cos(C) + 0.5 \times A \times
(\cos(C-M) + \cos(C+M)) \]

$A$, called the \emph{modulation index}, controls the size of the
sidebands.  Note the similarity of this equation to that for tremolo.


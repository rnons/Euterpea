{-# LANGUAGE Arrows #-}
module Euterpea.IO.MUI.Guitar where
import Euterpea.IO.MUI.UIMonad
import Euterpea.IO.MUI.Widget
import Euterpea.IO.MUI.UISF
import Euterpea.IO.MUI.SOE
import Euterpea.IO.MIDI
import Euterpea.Music.Note.Music hiding (transpose)
import Euterpea.Music.Note.Performance
import Control.SF.AuxFunctions
import Control.Arrow
import Euterpea.IO.MUI.InstrumentBase
import qualified Codec.Midi as Midi
import Data.Maybe
import qualified Data.Char as Char

--Note, only valid for standard US keyboards:
--Also, this is an ugly hack that can't stay
--it's mostly to test the new key events
toUpper :: Char -> Char
toUpper c = case lookup c keyMap of
                Just c' -> c'
                Nothing -> Char.toUpper c
            where keyMap = [('`', '~'), ('1', '!'), ('2', '@'), ('3', '#'), ('4', '$'),
                            ('5', '%'), ('6', '^'), ('7', '&'), ('8', '*'), ('9', '('),
                            ('0', ')'), ('-', '_'), ('=', '+'), ('[', '{'), (']', '}'),
                            ('|', '\\'), ('\'', '\"'), (';', ':'), ('/', '?'), ('.', '>'),
                            (',', '<')]

isUpper :: Char -> Bool
isUpper c = toUpper c == c

-- first fret's width and height
fw,fh,tw,th :: Int
(fw, fh) = (90, 45)
(tw, th) = (8, 16)

type KeyType = Int
type GuitarKeyMap = [(String, Pitch, Char)]

drawFret [] ((x, y), (w, h)) = nullGraphic
drawFret ((t, b):cs) ((x, y), (w, h)) =
    drawFret cs ((x + 1, y + 1), (w - 2, h )) //
    withColor' t (line (x, y) (x, y + h)) //
    withColor' b (line (x + w - 1, y) (x + w - 1, y + h))

drawString down ((x, y), (w, h)) =
    withColor Black (if down then arc (x,midY+2) (x+w, midY-2) (-180) 180
                             else line (x-1, y+ h `div` 2) (x+w, y+h `div` 2)) //
    if down then withColor Blue (ellipse (midX - d, midY - d) (midX + d, midY + d)) else nullGraphic
    where d = 10
          midX = x + w `div` 2
          midY = y + h `div` 2

drawHead :: Int -> UISF () ()
drawHead 0 = proc _ -> returnA -< ()
drawHead n = topDown $  proc _ -> do
    ui <- mkUISF aux -< ()
    ui' <- drawHead (n-1) -< ()
    returnA -< ()
    where action ((x,y),(w,h)) = withColor Black $ line (x, y + h `div` 2 + 5 * (3 - n)) (x + w, y + h `div` 2)
          aux x (ctx,f,t,inp) = (Layout 0 0 fw fh fw fh, True, f, justGraphicAction $ action (bounds ctx), nullCD, ())

mkKey :: Char -> KeyType -> UISF KeyData KeyState
mkKey c kt =
    mkWidget (KeyState False False False 127, Nothing) d draw (const nullSound) inputInj process outputProj where
        d = Layout 0 0 0 minh minw minh
        (minh, minw) = (fh, fw - kt * 3)

        draw rect inFocus (kb, showNote) =
            let isDown = isKeyDown kb
                box@((x,y),(w,h)) = rect
                x' = x + (w - tw) `div` 2 + if isDown then 0 else -1
                y' = y + h `div` 5 + (h - th) `div` 2 + if isDown then 0 else -1
                drawNotation s = withColor Red $ text (x' + (1 - length s) * tw `div` 2, y' - th) s
             in (withColor Blue $ text (x', y') [c]) //
                (maybe nullGraphic drawNotation showNote) //
                (drawString isDown box) //
                drawFret popped box

        inputInj = (,)

        process ((kd,(kb,_)),(ctx,evt)) = ((kb'', notation kd), kb /= kb'') where
            kb' = if isJust (pressed kd) then kb { song = fromJust $ pressed kd } else kb
            kb'' = case evt of
                Key (CharKey c') down ms ->
                    if detectKey c' (shift ms)
                    then kb' { keypad = down, vel = 127 }
                    else kb'
                Button pt True down ->
                    case (mouse kb', down, pt `inside` box) of
                        (False, True, True) -> kb' { mouse = True,  vel = getVel pt box }
                        (True, False, True) -> kb' { mouse = False, vel = getVel pt box }
                        otherwise -> kb'
                MouseMove pt ->
                    if pt `inside` box
                    then kb'
                    else kb' { mouse = False }
                otherwise -> kb'
                where box = bounds ctx
                      getVel (u,v) ((x,y),(w,h)) = 127 - round (87 * (abs (fromIntegral u - fromIntegral (2 * x + w) / 2) / (fromIntegral w / 2)))
                      detectKey c' s = toUpper c == toUpper c' && isUpper c == s -- This line should be more robust

        outputProj st = (fst st, st)

mkKeys :: AbsPitch -> [(Char, KeyType, AbsPitch)] -> UISF (Bool, InstrumentData) (SEvent [(AbsPitch, Bool, Midi.Velocity)])
mkKeys _ [] = proc _ -> returnA -< Nothing
mkKeys free ((c,kt,ap):ckas) = proc (pluck, instr) -> do
    msg <- unique <<< mkKey c kt -< getKeyData ap instr
    let on  = maybe False isKeyPlay msg
        ret | pluck     = if on then [(ap, True, maybe 127 vel msg)] else [(free, True, 127)]
            | not pluck = [(ap, False, maybe 0 vel msg)]
    msgs <- mkKeys free ckas -< (pluck, instr)
    returnA -< fmap (const ret) msg ~++ msgs

mkString :: ([Char], Pitch, Char) -> UISF InstrumentData (SEvent [(AbsPitch, Bool, Midi.Velocity)])
mkString (frets, freePitch, p) = leftRight $ proc insData -> do
    isPluck <- pluckString p -< ()
    msgs <- mkKeys freeap (zip3 frets [1..] [freeap+1..]) -< (isPluck, insData)
    returnA -< msgs
    where freeap = absPitch freePitch

pluckString :: Char -> UISF () Bool
pluckString c = mkWidget False nullLayout draw (const nullSound) (const id) process (\x -> (x,x)) where
    draw b@((x,y),(w,h)) inFocus down =
        let x' = x + (w - tw) `div` 2 + if down then 0 else -1
            y' = y + (h - th) `div` 2 + if down then 0 else -1
         in withColor (if down then White else Black) $ block ((0,0),(10,10))

    process (s,(ctx,evt)) = (s', s /= s') where
        s' = case evt of
            Button pt True down -> down
            Key (CharKey c') down _ ->
                down && c == c'
            otherwise -> s

guitar :: GuitarKeyMap -> Midi.Channel -> UISF (InstrumentData,EMM) EMM
guitar spcList chn = focusable $ leftRight $ proc (instr, emm) -> do
    let emm' = fmap (setChannel chn) emm
    h <- drawHead (length spcList) -< ()
    frets <- mkStrings spcList -< instr { keyPairs = fmap mmToPair emm' }
    returnA -< fmap (pairToMsg chn) frets ~++ emm'
    where mkStrings [] = proc _ -> returnA -< Nothing
          mkStrings (spc:spcs) = topDown $ proc instrData -> do
              msg <- mkString spc -< instrData
              msgs <- mkStrings spcs -< instrData
              returnA -< msg ~++ msgs

string1, string2, string3, string4, string5, string6 :: (String, Pitch, Char)
string6 = ("1qaz__________", (E,5), '\b')
string5 = ("2wsx__________", (B,4), '=')
string4 = ("3edc__________", (G,4), '-')
string3 = ("4rfv__________", (D,4), '0')
string2 = ("5tgb__________", (A,3), '9')
string1 = ("6yhn__________", (E,3), '8')

sixString = reverse [string1, string2, string3, string4, string5, string6]

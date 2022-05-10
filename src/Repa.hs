{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE BangPatterns  #-}
module Repa where

import Data.Array.Repa as R
import Data.List as L
import Data.Sequence as S
import Codec.Picture
import Data.Array.Repa.Stencil
import Data.Array.Repa.Stencil.Dim2
import Control.Monad
import Control.Parallel.Strategies
import Data.Vector as V hiding (mapM)
import Data.Array.Repa.Repr.Unboxed as U
import JuicyRepa
import Juicy
import Control.Parallel
import System.Random


{--
  _____                _   
 |_   _|   ___   ___  | |_ 
   | |    / _ \ / __| | __|
   | |   |  __/ \__ \ | |_ 
   |_|    \___| |___/  \__|
                           
--}

test :: IO ()
test = do
    putStrLn "Iniciando Test Fichero Repa.hs"
    -- img <- readImageIntoRepa "data/images/saitama.png"
    img <- readImageIntoRepa "data/images/lena_color.png"
    {-FIltro Gaussiano-}
    -- blurImg <- mapM (promote >=> blur 4 >=> demote) img
    -- savePngImage "blursaitama.png" (ImageRGB8 $ repaToJuicy blurImg)

    {-Filtro Sobel-}
    imgGrey <- toGrayScale img
    output <- sobel imgGrey
    savePngImage "sobelrepa.png" (ImageYF $ exportBW output)

    {-Histograma (Sequence)-}
    -- hstSequence <- generateHistograms <$> mapM promoteInt img
    -- print hstSequence

    {-Histograma (Vector)-}
    -- hstVector <- generateHists <$> mapM promoteInt img
    -- print hstVector

    {-Black and White-}
    -- blackAndWhite <- toGrayScale img
    -- savePngImage "blackandwhite.png" (ImageYF $ exportBW blackAndWhite)

    -- img2 <- readImageIntoRepa "NZ6DR.jpg"
    -- rojo <- promote $  L.head img2
    -- aa <- passes 4 edgeFilter rojo
    -- aa2 <- demote aa
    -- savePngImage "example.png" (ImageY8 $ exportBand aa2)


    putStrLn "El test ha ido correctamente"
    

promote :: Monad m => Channel Pixel8 -> m (Channel Float)
promote  = computeP . R.map func
    where {-# INLINE func #-}
          func :: Pixel8 -> Float
          func x = fromIntegral x
{-# NOINLINE promote #-}


demote :: Monad m => Channel Float -> m (Channel Pixel8)
demote =  computeP . R.map func
    where {-# INLINE func #-}
          func :: Float -> Pixel8
          func x = fromIntegral (truncate x :: Int)
{-# NOINLINE demote #-}

promoteInt :: Channel Pixel8 -> IO (Channel Int)
promoteInt = computeP . R.map func
    where  {-# INLINE func #-}
           func :: Pixel8 -> Int 
           func x  = fromIntegral x
{-# NOINLINE promoteInt #-}

-- promotesToInt :: ImgRGB Pixel8 -> IO (ImgRGB Int)
-- promotesToInt = mapM promoteInt
--     where promoteInt :: Channel Pixel8 -> IO (Channel Int)
--           promoteInt = computeP . R.map func
--             where  func :: Pixel8 -> Int 
--                    func x  = fromIntegral x

-- demotesInt :: ImgRGB Int -> IO (ImgRGB Pixel8)
-- demotesInt = mapM demoteInt
--     where demoteInt :: Channel Int -> IO (Channel Pixel8)
--           demoteInt = computeP . R.map func
--             where func :: Int -> Pixel8
--                   func x = fromIntegral x

{--
  _   _   _         _                                              
 | | | | (_)  ___  | |_    ___     __ _   _ __    __ _   _ __ ___  
 | |_| | | | / __| | __|  / _ \   / _` | | '__|  / _` | | '_ ` _ \ 
 |  _  | | | \__ \ | |_  | (_) | | (_| | | |    | (_| | | | | | | |
 |_| |_| |_| |___/  \__|  \___/   \__, | |_|     \__,_| |_| |_| |_|
                                  |___/                            
--}

{-Tipos de Datos-}
type Histogram = Seq Int
type Histograms = [Histogram]

-- 1º Versión (Cálculo de Histogramas secuencialmente)
-- generateHistograms :: ImgRGB -> Histograms
-- generateHistograms = Prelude.map generateHistogram

-- 2º version (Cálculo de Histogramas de manera paralela)
-- Nivel grano grueso: haz el cálculo del histograma de cada canal en paralelo. 
-- Esto solo llevaría a hacerlo tan solo 3 veces más rápido.

generateHistograms :: ImgRGB Int-> Histograms
generateHistograms xs =
    let bs = Prelude.map generateHistogram xs
        cs = bs `using` parList rdeepseq
        in cs

generateHistogram :: Channel Int -> Histogram
generateHistogram c =
    let (Z :. w :. h)  = R.extent c
        zero = S.replicate 256 0 -- O(logn)
    in L.foldl' (\hst (x,y) ->
        let val = R.unsafeIndex c (Z :. x :. y)
            cont = hst `S.index` val
        in S.update val (cont+1) hst)
        zero
        [(x,y) | x<-[0..w-1],y<-[0..h-1]]

-- 3º Version Histograma granuelado fino

{-- Nivel grano fino: haz el cálculo de cada fila de la imagen en paralelo. Además, hazlo también para cada canal en paralelo.
De esta forma, si nos fijamos en un canal, obtendrías tantos histogramas como filas tenga la imagen. Después, queda hacer
una suma de cada entrada de los histogramas para obtener el histograma final. 
La operación de suma también se puede paralelizar ya que es un reduce.
Una solución que generalice lo anterior y que haga un histograma por cada N filas. 
Después en tu experimentos juega con esa N, a ver cuando va más rápido.
--}
-- Para esta versión necesitamos una Estructura distinta de datos
type HVector = Vector Int
type HVectors = [HVector]

generateHists :: ImgRGB Int-> [HVector]
generateHists xs =
    let bs = Prelude.map generateHist xs
        cs = bs `using` parList rdeepseq
        in cs

generateHist :: Channel Int -> HVector
generateHist band = pfold (V.zipWith (+)) (generateRows band)

generateRows :: Channel Int -> [HVector]
generateRows band =
    let (Z :. w :. h) = R.extent band
        bs = Prelude.map (generateRow band) [0..w-1]
        cs = bs `using` parList rdeepseq
        in cs


generateRow :: Channel Int -> Int -> Vector Int
generateRow band i=
    let zero = V.replicate 256 0 -- O(n)
        fila =  R.toList $ R.slice band  (Any :. (i::Int) :. All) -- Seleccionamos la Fila [12,3,4,4,5]
        l = L.zip fila [1,1..]
    in V.accum (+) zero l -- Crearemos el histograma con los valores correspondientes


-- Función que nos hace un fold de manera paralela
pfold :: (a -> a -> a) -> [a] -> a
pfold _ [x] = x
pfold mappend xs  = (ys `par` zs) `pseq` (ys `mappend` zs) where
  len = L.length xs
  (ys', zs') = L.splitAt (len `div` 2) xs
  ys = pfold mappend ys'
  zs = pfold mappend zs'

{- 
  ____     ___    __        __
 | __ )   ( _ )   \ \      / /
 |  _ \   / _ \/\  \ \ /\ / / 
 | |_) | | (_>  <   \ V  V /  
 |____/   \___/\/    \_/\_/   
                              
FORMULA PARA SACAR LA LUMINOSIDAD
    Y' = 0.2989 R + 0.5870 G + 0.1140 B 
    (https://en.wikipedia.org/wiki/Grayscale)
-}

-- 1º Version usando zipwith
-- toGrayScale :: ImgRGB Int -> IO (Channel Float)
-- toGrayScale img = R.computeP $ R.zipWith (+) b (R.zipWith (+) r g)
--     where r = generateComponentB 0 (L.head img)
--           g = generateComponentB 1 (img !! 1)
--           b = generateComponentB 2 (L.last img)

-- generateComponentB :: Int -> Channel Int -> Array D DIM2 Float
-- generateComponentB ind = R.map (\v -> (fromIntegral (fromIntegral v ::Int) / 255)*val)
--     where val = [0.2989,0.5870,0.1140] !! ind

-- 2º Version usando zip3
luminance :: (Pixel8, Pixel8, Pixel8) -> Float
{-# INLINE luminance #-}
luminance (r, g, b)
 = let  r'      = fromIntegral (fromIntegral r) / 255
        g'      = fromIntegral (fromIntegral g) / 255
        b'      = fromIntegral (fromIntegral b) / 255
   in   r' * 0.3 + g' * 0.59 + b' * 0.11

toGrayScale :: ImgRGB Pixel8 -> IO (Channel Float)
toGrayScale [r,g,b] = R.computeP . R.map luminance  $ U.zip3 r g b
toGrayScale _ = error "No se puede hacer debido a que no hay los canales suficientes para realizar el blanco y negro"
{-# NOINLINE toGrayScale #-}


{-- 

   ____                               _                     _       _                
  / ___|   __ _   _   _   ___   ___  (_)   __ _   _ __     | |__   | |  _   _   _ __ 
 | |  _   / _` | | | | | / __| / __| | |  / _` | | '_ \    | '_ \  | | | | | | | '__|
 | |_| | | (_| | | |_| | \__ \ \__ \ | | | (_| | | | | |   | |_) | | | | |_| | | |   
  \____|  \__,_|  \__,_| |___/ |___/ |_|  \__,_| |_| |_|   |_.__/  |_|  \__,_| |_|   
                                                                                     
--}

--- Para poder realizar el blur, lo primero que debemos hacer es como vamos a aplicar
-- el filtro de esto -- sigma=1, kernel_radius = 5
-- https://observablehq.com/@jobleonard/gaussian-kernel-calculater
-- [0.06136,0.24477,0.38774,0.24477,0.06136]
-- Como Stencil2 no acepta decimales, nuestra lista se quedará de la siguiente manera
    --[1/16, 4/16,]
-- 

blurX :: Monad m => Channel Float -> m (Channel Float)
blurX img = R.computeP 
            $ R.smap (/ 16) -- un map más eficiente
            $ forStencil2  BoundClamp img
              [stencil2| 1 4 6 4 1 |]
{-# NOINLINE blurX #-}


blurY :: Monad m => Channel Float -> m (Channel Float)
blurY img =  R.computeP
             $ R.smap(/16)
             $ forStencil2 BoundClamp img
               [stencil2|    1
                             4
                             6
                             4
                             1 |]
{-# NOINLINE blurY #-}


blur :: Monad m => Int -> Channel Float -> m (Channel Float)
blur !steps imgInit = go steps imgInit
    where go !0 !img = return img
          go !n !img = 
              do sepx <- blurX img
                 sepy <- blurY sepx
                 go (n-1) sepy   
{-# NOINLINE blur #-}


{-
  ____            _              _ 
 / ___|    ___   | |__     ___  | |
 \___ \   / _ \  | '_ \   / _ \ | |
  ___) | | (_) | | |_) | |  __/ | |
 |____/   \___/  |_.__/   \___| |_|
                                   
-}
-- https://es.wikipedia.org/wiki/Operador_Sobel#Formulaci%C3%B3n

-- Cálculo de Gx
gradX :: Monad m => Channel Float -> m (Channel Float)
gradX img = R.computeP
            $ forStencil2 BoundClamp img
              [stencil2| -1 0 1
                         -2 0 2 
                         -1 0 1 |]
{-# NOINLINE gradX #-}

-- Calculo de Gy
gradY :: Monad m => Channel Float -> m (Channel Float)
gradY img = R.computeP
            $ forStencil2 BoundClamp img
              [stencil2| -1 -2 -1
                          0  0  0 
                          1  2  1 |]
{-# NOINLINE gradY #-}
-- Normalmente, Sobel usa 2 kernels 3x3, aunque según wikipedia,
-- cada kernel podemos descomponerlo en otros 2 filtros.

-- Magnitude G = Sqrt (Gx^2 + Gy^2)
magnitude :: Float -> Float -> Float
magnitude x y = sqrt (x*x + y*y)

-- Para usar este algoritmo, en primer lugar debemos sacar la luminosidad
-- de la imagen RGB (pasarlo a blanco y negro)
sobel :: Monad m => Channel Float -> m (Channel Float)
sobel img = do
    gx <- gradX img
    gy <- gradY img
    R.computeP $ R.zipWith (magnitude) gx gy 
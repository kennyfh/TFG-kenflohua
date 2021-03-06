module VideoSummarization where

-- Importación de módulos
import Juicy as J
import JuicyAccelerate as JA
import Codec.Picture as P
import Control.Parallel.Strategies
import Accelerate as A
import Data.Array.Accelerate
import Prelude as P
import Data.Array.Accelerate.Interpreter as I -- TODO: modificar esto por el interprete de CUDA 
import qualified Data.Array.Accelerate as A


test :: IO()
test = do
    putStrLn "Welcome! Write the path of the video you want to summarize"
    vpath <- getLine -- path del video al que vamos a construir los frames
    -- putStrLn "Write k segments"
    -- k <- getLine
    let k = "7" -- TODO: modificar k
    -- -- 1º Creamos todos los frames
    xs <-  getAllFrames vpath -- videos/video1.mp4
    -- 2º división de los frames en  k segmentos
    let segments = generateSegments (read k::Int) xs
    print $ P.length segments

    -- 3º Tomaremos el primer frame de cada segmento, este será nuestro marco representativo
    -- Lo denotaremos como x0,...,xn
    let xn = fstFragSeg segments
    let acc_xn = accelerateFrames xn -- Transformamos x0,x1,....xn en formato que pueda leer la GPU
    -- 4º Transformación de histogramas
    let histograms = createHistograms acc_xn -- y0,y1,.....,yn
    let xs = P.map I.run histograms

    -- Xº Generamos el resumen del vídeo
    -- saveVideo frames "video.mp4"
    putStrLn "End of VideoSummarization.hs"

{-FUNCIONES AUXILIARES-}


createHistograms :: [Matrix RGB] -> [Acc (Matrix RGB)]
createHistograms = P.map A.use



-- Función que genera los segmentos de forma palalela
generateSegments :: Int -> [Image PixelRGB8] -> [[Image PixelRGB8]]
generateSegments k [] = []
generateSegments k xs = P.take k xs:generateSegments k (P.drop k xs)

-- Función que nos da el primer frame de cada segmento, siguiendo el algoritmo
fstFragSeg :: [[Image PixelRGB8]] -> [Image PixelRGB8]
fstFragSeg xs =
    let bs = P.map head xs
        cs = bs `using` parList rdeepseq
        in cs

--Función que nos transforma todos los frames en JuixyPixels en Accelerate
accelerateFrames :: [Image PixelRGB8] -> [Matrix RGB]
accelerateFrames xs =
    let bs = P.map JA.imgToArr xs
        cs = bs `using` parList rdeepseq
        in cs

-- -- Aletoriedad en Haskell
-- -- https://www.glc.us.es/~jalonso/vestigium/i1m2019-aleatoriedad-en-haskell/
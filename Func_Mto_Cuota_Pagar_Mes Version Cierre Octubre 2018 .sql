
ALTER FUNCTION [dbo].[Func_Mto_Cuota_Pagar_Mes] 
(
	-- Parametros
	@JTS_OID AS NUMERIC(10,0),
	@FechaDesem AS DATETIME,
	@IndicadorCDR AS INT
)
RETURNS FLOAT
AS
BEGIN
	-- Bloque de Declaracion
	DECLARE	@FechaVencimiento AS DATETIME,
			@Mto_Cuota_Mes FLOAT,
			@Mto_Cuota_Interes FLOAT,
			@Mto_Cuota_Capital FLOAT,
			@Mensual BIT,
			@Alvencimiento BIT,
			@OtrasFrecuencias BIT,
			@CuotasVigentes BIT,
			@Fecha1  SMALLDATETIME,
			@Fecha2 SMALLDATETIME
			
	SELECT @FechaVencimiento = MAX(bpo.C2302) FROM BS_PLANPAGOS bpo WHERE bpo.SALDO_JTS_OID = @JTS_OID AND bpo.TZ_LOCK =0;

	-- EN caso que el credito este cancelado no realizar ningun calculo
	IF ( (SELECT s.C1604 FROM SALDOS s WHERE s.TZ_LOCK =0 AND s.JTS_OID =@JTS_OID ) =0 )
	       BEGIN
	       		RETURN 0;
	       END
	
	
		SET @Fecha1= (SELECT  CONVERT( SMALLDATETIME, '01/'+''+ CONVERT(nvarchar(2), month(p.FECHAPROCESO)) +'/'+ CONVERT(CHAR(4),  YEAR		(p.FECHAPROCESO))) FROM PARAMETROS p)
		SET @Fecha2 = (SELECT p.FECHAPROCESO  FROM PARAMETROS p)
	SELECT @FechaDesem  = S.C1620 FROM SALDOS s WHERE s.JTS_OID = @JTS_OID
	SELECT @FechaVencimiento = MAX(bpo.C2302) FROM BS_PLANPAGOS bpo WHERE bpo.SALDO_JTS_OID = @JTS_OID AND bpo.TZ_LOCK =0

		/* 
		* s.C1677 ='C' Irregular
		* s.C1677 =' ' Al vencimiento
		* s.C1728 = 'N' THEN 'Vigente'
		*/	

		-- Indicador Al vencimiento
		SELECT  @Alvencimiento = IIF( s.C1677 =' ',1,0) 
		FROM SALDOS s
		WHERE S.JTS_OID = @JTS_OID AND s.TZ_LOCK =0		 		
		
		-- Indicador Mensuales 
		SELECT @mensual = CASE WHEN SS.C5034 =30 AND s.c1677 !='C' THEN 1 ELSE 0 END
		FROM SL_SOLICITUDCREDITO ss
		INNER JOIN SALDOS s ON s.CUENTA =ss.C5002
		WHERE  s.JTS_OID = @JTS_OID
		
		-- Indicador para las otras frecuencias
		SELECT @OtrasFrecuencias = IIF(@Alvencimiento =0 AND @Mensual =0,1,0)
	
	
		-- Cuotas Vigentes
		SELECT @CuotasVigentes = 	iif( COUNT(*) >0,1,0 ) 
				FROM BS_PLANPAGOS bp2 WITH (NOLOCK) 
				where bp2.TZ_LOCK =0 AND bp2.SALDO_JTS_OID =@JTS_OID 
				AND (bp2.C2309 + bp2.C2310) > 0 
				AND CONVERT( SMALLDATETIME, CONVERT(CHAR(10),bp2.c2302,103))>@Fecha1
				
	
		
		IF (@OtrasFrecuencias =1 )
		BEGIN
			-- Mensualizar las Cuotas
			-- ======================================================================================================
			-- Anual,BimestralCuatrimestral,Irregular,Quincenal,Semanal,Semestral,Trimestral
			-- ======================================================================================================
			
			-- Capital
			SELECT @Mto_Cuota_Capital = sum(isnull(bpo.C2309,0))/(DATEDIFF(dd,@FechaDesem,@FechaVencimiento)*1.0/30)
			FROM BS_PLANPAGOS bpo WITH (NOLOCK)
			WHERE bpo.SALDO_JTS_OID = @JTS_OID AND bpo.TZ_LOCK = 0
			-- Interes
			SELECT @Mto_Cuota_Interes = sum(isnull(bpo.C2310,0))/(DATEDIFF(dd,@FechaDesem,@FechaVencimiento)*1.0/30)
			FROM BS_PLANPAGOS bpo WITH (NOLOCK)
			WHERE bpo.SALDO_JTS_OID = @JTS_OID AND bpo.TZ_LOCK = 0

		END
		
		IF ( @Mensual =1 )
		BEGIN
			
			-- Creditos con cuotas vigentes
			IF (@CuotasVigentes=1)
			BEGIN
				-- Capital
				SELECT TOP (1) @Mto_Cuota_Capital =  bp.C2309 
				FROM BS_PLANPAGOS bp WITH (NOLOCK)
				WHERE bp.C2309>0 AND bp.TZ_LOCK =0	AND bp.SALDO_JTS_OID =@JTS_OID
				AND CONVERT( SMALLDATETIME, CONVERT(CHAR(10),bp.c2302,103)) BETWEEN @Fecha1 AND @Fecha2	
				ORDER BY BP.C2302 ASC			
				
				-- Interes
				SELECT TOP (1) @Mto_Cuota_Interes =  bp.C2310 
				FROM BS_PLANPAGOS bp WITH (NOLOCK)
				WHERE bp.C2310>0 AND bp.TZ_LOCK =0	AND bp.SALDO_JTS_OID =@JTS_OID
				AND CONVERT( SMALLDATETIME, CONVERT(CHAR(10),bp.c2302,103)) BETWEEN @Fecha1 AND @Fecha2	
				ORDER BY BP.C2302 ASC	
			END						
			
			ELSE -- creditos vencidos y con todas sus cuotas vencidas
			BEGIN
				-- Capital
				SELECT TOP (1) @Mto_Cuota_Capital =  bp.C2309 
				FROM BS_PLANPAGOS bp WITH (NOLOCK)
				WHERE bp.C2309>0 AND bp.TZ_LOCK =0	AND bp.SALDO_JTS_OID =@JTS_OID
				ORDER BY BP.C2302 DESC -- PARA OBTENER LA ULTIMA CUOTA VENCIDA
				
				-- Interes
				SELECT TOP (1) @Mto_Cuota_Interes =  bp.C2310 
				FROM BS_PLANPAGOS bp WITH (NOLOCK)
				WHERE bp.C2310>0 AND bp.TZ_LOCK =0	AND bp.SALDO_JTS_OID =@JTS_OID
				ORDER BY BP.C2302 DESC -- PARA OBTENER LA ULTIMA CUOTA VENCIDA	
			END			 		
			
			
		END
		
		IF ( @Alvencimiento =1 )
			-- ======================================================================================================
			-- Al vencimiento (unica cuota) sin agrupar ni sumar
			-- ======================================================================================================
		BEGIN
			-- Creditos vigentes			
			IF (@CuotasVigentes =1)
			 BEGIN
				-- Capital
				SELECT @Mto_Cuota_Capital =  bp.C2309 
				FROM BS_PLANPAGOS bp WITH (NOLOCK)
				WHERE bp.C2309>0 AND bp.TZ_LOCK =0	AND bp.SALDO_JTS_OID =@JTS_OID
				AND CONVERT( SMALLDATETIME, CONVERT(CHAR(10),bp.c2302,103)) BETWEEN @Fecha1 AND @Fecha2				
				
				-- Interes
				SELECT @Mto_Cuota_Interes =  bp.C2310 
				FROM BS_PLANPAGOS bp WITH (NOLOCK)
				WHERE bp.C2310>0 AND bp.TZ_LOCK =0	AND bp.SALDO_JTS_OID =@JTS_OID
				AND CONVERT( SMALLDATETIME, CONVERT(CHAR(10),bp.c2302,103)) BETWEEN @Fecha1 AND @Fecha2													 				 	
			 END			

			ELSE	 -- Cuotas Vencidas
			BEGIN
				-- Capital
				SELECT @Mto_Cuota_Capital =  bp.C2309 
				FROM BS_PLANPAGOS bp WITH (NOLOCK)
				WHERE bp.C2309>0 AND bp.TZ_LOCK =0	AND bp.SALDO_JTS_OID =@JTS_OID
				-- Interes
				SELECT @Mto_Cuota_Interes =  bp.C2310 
				FROM BS_PLANPAGOS bp WITH (NOLOCK)
				WHERE bp.C2310>0 AND bp.TZ_LOCK =0	AND bp.SALDO_JTS_OID =@JTS_OID
				
			END
			
		END

	IF (@IndicadorCDR =1)
	BEGIN
		SET @Mto_Cuota_Mes = isnull(@Mto_Cuota_Capital,0) + ISNULL(@Mto_Cuota_Interes,0)
	END
	
	IF (@IndicadorCDR =2)
	BEGIN
		SET @Mto_Cuota_Mes = isnull(@Mto_Cuota_Capital,0)
	END
	
	IF (@IndicadorCDR =3)
	BEGIN
		SET @Mto_Cuota_Mes = ISNULL(@Mto_Cuota_Interes,0)
	END

	-- Return the result of the function
	RETURN @Mto_Cuota_Mes;

END


cat <<EOF
OUTPUT_FORMAT("${OUTPUT_FORMAT}")
OUTPUT_ARCH(${ARCH})

/* Code and data, both 64k */

SECTIONS 				
{ 					
.text ${RELOCATING+ 0x10000 } :
	{ 					
	  *(.text) 				
	*(.rdata); 
	  *(.strings)
	___ctors = . ;
	*(.ctors)
	___ctors_end = . ;
	___dtors = . ;
	*(.dtors)
	___dtors_end = . ;
   	 ${RELOCATING+ _etext = . ; }
	}


.data  ${RELOCATING+ 0x20000 } :
	{
	*(.data)
	${RELOCATING+ _edata = . ; }
	} 


.bss  ${RELOCATING+ .} :
	{
	${RELOCATING+ __start_bss = . ; }
	*(.bss)
	*(COMMON)
	${RELOCATING+ _end = . ;  }
	}

.stack  ${RELOCATING+ 0x2fff0} :
	{
	${RELOCATING+ _stack = . ; }
	*(.stack)
	} 

  .stab  . (NOLOAD) : 
  {
    [ .stab ]
  }
  .stabstr  . (NOLOAD) :
  {
    [ .stabstr ]
  }
}
EOF





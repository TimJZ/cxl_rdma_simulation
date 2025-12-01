// (C) 2001-2024 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files from any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License Subscription 
// Agreement, Intel FPGA IP License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Intel and sold by 
// Intel or its authorized distributors.  Please refer to the applicable 
// agreement for further details.


// Copyright 2024 Intel Corporation.
//
// THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
// COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
// EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
///////////////////////////////////////////////////////////////////////
//
// THIS IS AN AUTO-GENERATED FILE!!!!!
//
// INTEL PSG INTERNAL USE : DO NOT EDIT THIS AUTO-GENERATED, VERSION CONTROLLED FILE
// Please goto <MODEL_ROOT/scripts and run 'python gen_example_design_common_pkg.py'
//   to run the script that updates this version controlled file
// Please check in updated file.
//
// CUSTOMER USE : This make structs and parameters previously hidden behind encryption
//   under the CXLIP boundary visible. Instructions and warnings on editing these structs
//   and parameters will be provided in-line where considered necessary.
//

package cafu_common_pkg;

// @@copy for common_afu_pkg@@start
    localparam CAFU_AFU_AXI_BURST_WIDTH            = 2;
    localparam CAFU_AFU_AXI_CACHE_WIDTH            = 4;
    localparam CAFU_AFU_AXI_LOCK_WIDTH             = 2;
    localparam CAFU_AFU_AXI_MAX_ADDR_USER_WIDTH    = 5;
    localparam CAFU_AFU_AXI_MAX_ADDR_WIDTH         = 64;
    localparam CAFU_AFU_AXI_MAX_BRESP_USER_WIDTH   = 4;
    localparam CAFU_AFU_AXI_MAX_BURST_LENGTH_WIDTH = 10;
    localparam CAFU_AFU_AXI_MAX_DATA_USER_WIDTH    = 4;
    localparam CAFU_AFU_AXI_MAX_DATA_WIDTH         = 512;
    localparam CAFU_AFU_AXI_MAX_ID_WIDTH           = 12;
    localparam CAFU_AFU_AXI_PROT_WIDTH             = 3;
    localparam CAFU_AFU_AXI_QOS_WIDTH              = 4;
    localparam CAFU_AFU_AXI_REGION_WIDTH           = 4;
    localparam CAFU_AFU_AXI_RESP_WIDTH             = 2;
    localparam CAFU_AFU_AXI_SIZE_WIDTH             = 3;
    localparam CAFU_AFU_AXI_BUSER_WIDTH            = 4;
    localparam CAFU_AFU_AXI_AWATOP_WIDTH           = 6;

//------------------------------------------------------------------------ 
//  AMBA AXI and ACE Protocol Specitifcation, Issue 4, 2013
//  page 47, A3.4.1, Access Permissions
//  Table A3-2 Burst size encoding    
//------------------------------------------------------------------------
    typedef enum logic [CAFU_AFU_AXI_SIZE_WIDTH-1:0] {
        esize_CAFU_128          = 3'b100,
        esize_CAFU_256          = 3'b101,
        esize_CAFU_512          = 3'b110,
        esize_CAFU_1024         = 3'b111
    } t_cafu_axi4_burst_size_encoding;

//------------------------------------------------------------------------ 
//  AMBA AXI and ACE Protocol Specitifcation, Issue 4, 2013
//  page 48, A3.4.1, Access Permissions
//  Table A3-3 Burst type encoding    
//------------------------------------------------------------------------ 
    typedef enum logic [CAFU_AFU_AXI_BURST_WIDTH-1:0] {
        eburst_CAFU_FIXED     = 2'b00,
        eburst_CAFU_INCR      = 2'b01,
        eburst_CAFU_WRAP      = 2'b10,
        eburst_CAFU_RSVD      = 2'b11
    } t_cafu_axi4_burst_encoding;


// @@copy for common_afu_pkg@@start
//------------------------------------------------------------------------ 
//  AMBA AXI and ACE Protocol Specitifcation, Issue 4, 2013
//  page 73, A4.7, Access Permissions
//  Table A4-6 Protection Encoding    
//------------------------------------------------------------------------
    typedef enum logic [CAFU_AFU_AXI_PROT_WIDTH-1:0] {
        eprot_CAFU_UNPRIV_SECURE_DATA        = 3'b000,
        eprot_CAFU_UNPRIV_SECURE_INST        = 3'b001,
        eprot_CAFU_UNPRIV_NONSEC_DATA        = 3'b010,
        eprot_CAFU_UNPRIV_NONSEC_INST        = 3'b011,
        eprot_CAFU_PRIV_SECURE_DATA          = 3'b100,
        eprot_CAFU_PRIV_SECURE_INST          = 3'b101,
        eprot_CAFU_PRIV_NONSEC_DATA          = 3'b110,
        eprot_CAFU_PRIV_NONSEC_INST          = 3'b111
    } t_cafu_axi4_prot_encoding;

//------------------------------------------------------------------------ 
//  AXI AFU HAS, page 32
//------------------------------------------------------------------------ 
    typedef enum logic [CAFU_AFU_AXI_QOS_WIDTH-1:0] {
        eqos_CAFU_BEST_EFFORT           = 4'h0,
        eqos_CAFU_USER_LOW              = 4'h4,
        eqos_CAFU_USER_HIGH             = 4'h8,
        eqos_CAFU_LOW_LATENCY           = 4'hC
    } t_cafu_axi4_qos_encoding;

//------------------------------------------------------------------------ 
//  AMBA AXI and ACE Protocol Specitifcation, Issue 4, 2013
//  page 67
//  Table A4-5 MEMORY TYPE ENCODING
//------------------------------------------------------------------------ 
    typedef enum logic [CAFU_AFU_AXI_CACHE_WIDTH-1:0] {
        ecache_aw_CAFU_DEVICE_NON_BUFFERABLE                 = 4'b0000,
        ecache_aw_CAFU_DEVICE_BUFFERABLE                     = 4'b0001,
        ecache_aw_CAFU_NORMAL_NON_CACHEABLE_NON_BUFFERABLE   = 4'b0010,
        ecache_aw_CAFU_NORMAL_NON_CACHEABLE_BUFFERABLE       = 4'b0011,
        ecache_aw_CAFU_WRITE_THROUGH_NO_ALLOCATE             = 4'b0110,
        ecache_aw_CAFU_WRITE_BACK_NO_ALLOCATE                = 4'b0111,
        ecache_aw_CAFU_WRITE_THROUGH_WRITE_ALLOCATE          = 4'b1110,
        ecache_aw_CAFU_WRITE_BACK_WRITE_ALLOCATE             = 4'b1111
    } t_cafu_axi4_awcache_encoding;

//------------------------------------------------------------------------ 
//  AMBA AXI and ACE Protocol Specitifcation, Issue 4, 2013
//  page 100, A7.4
//  Table A7-1 AXI3 atomic access encoding    
//------------------------------------------------------------------------ 
    typedef enum logic [CAFU_AFU_AXI_LOCK_WIDTH-1:0] {
        elock_CAFU_NORMAL            = 2'b00,
        elock_CAFU_EXECLUSIVE        = 2'b01,
        elock_CAFU_LOCKED            = 2'b10,
        elock_CAFU_RSVD              = 2'b11
    } t_cafu_axi4_lock_encoding;

//------------------------------------------------------------------------ 
//  AMBA AXI and ACE Protocol Specitifcation, Issue 4, 2013
//  page 67
//  Table A4-5 MEMORY TYPE ENCODING
//------------------------------------------------------------------------ 
    typedef enum logic [CAFU_AFU_AXI_CACHE_WIDTH-1:0] {
        ecache_ar_CAFU_DEVICE_NON_BUFFERABLE                 = 4'b0000,
        ecache_ar_CAFU_DEVICE_BUFFERABLE                     = 4'b0001,
        ecache_ar_CAFU_NORMAL_NON_CACHEABLE_NON_BUFFERABLE   = 4'b0010,
        ecache_ar_CAFU_NORMAL_NON_CACHEABLE_BUFFERABLE       = 4'b0011,
        ecache_ar_CAFU_WRITE_THROUGH_NO_ALLOCATE             = 4'b1010,
        ecache_ar_CAFU_WRITE_BACK_NO_ALLOCATE                = 4'b1011,
        ecache_ar_CAFU_WRITE_THROUGH_READ_ALLOCATE           = 4'b1110,
        ecache_ar_CAFU_WRITE_BACK_READ_ALLOCATE              = 4'b1111
    } t_cafu_axi4_arcache_encoding;

//------------------------------------------------------------------------ 
//  AMBA AXI and ACE Protocol Specitifcation, Issue 4, 2013
//  page 57, A3.4.4
//  Table A3-4 RRESP and BRESP encoding   
//------------------------------------------------------------------------ 
    typedef enum logic [CAFU_AFU_AXI_RESP_WIDTH-1:0] {
        eresp_CAFU_OKAY              = 2'b00,
        eresp_CAFU_EXOKAY            = 2'b01,
        eresp_CAFU_SLVERR            = 2'b10,
        eresp_CAFU_DECERR            = 2'b11
    } t_cafu_axi4_resp_encoding;
endpackage : cafu_common_pkg
.libPaths("/data/CCBR_Pipeliner/db/PipeDB/Rlibrary_3.6.1_scRNA")
print(.libPaths())

library(Biobase)#,lib.loc="/data/CCBR_Pipeliner/db/PipeDB/Rlibrary_3.6.0_scRNA")
library(farver)#,lib.loc="/data/CCBR_Pipeliner/db/PipeDB/Rlibrary_3.6.0_scRNA")
library(S4Vectors)#,lib.loc="/data/CCBR_Pipeliner/db/PipeDB/Rlibrary_3.6.0_scRNA")
library("SingleR")#,lib.loc="/data/CCBR_Pipeliner/db/PipeDB/Rlibrary_3.6.0_scRNA")
library(scRNAseq)
library(SingleCellExperiment)
library("destiny")#,lib.loc="/data/CCBR_Pipeliner/db/PipeDB/Rlibrary_3.6.0_scRNA")
library("URD")#,lib.loc="/data/CCBR_Pipeliner/db/PipeDB/scrna_lib")
library("Seurat")
library(dplyr)
library(Matrix) 
library(tools)
library(stringr)
library(cluster)
library(scales)


args <- commandArgs(trailingOnly = TRUE)

matrix <- as.character(args[1])
#output = as.character(args[2])
outDirSeurat = as.character(args[2])
outDirMerge = as.character(args[3])
outImageDir=as.character(args[4])
specie = as.character(args[5])
resolution = as.character(args[6])
clusterAlg =  as.numeric(args[7])
annotDB = as.character(args[8])
nAnchors = as.numeric(args[9])
citeseq = as.character(args[10])
groups = as.character(args[11])
contrasts = as.character(args[12])

resolutionString = as.character(strsplit(gsub(",+",",",resolution),split=",")[[1]])
resolution = as.numeric(strsplit(gsub(",+",",",resolution),split=",")[[1]]) #remove excess commas, split into numeric vector

print(resolutionString)

file.names <- dir(path = matrix,pattern ="rds")

file.names = grep("doublets",file.names,invert=T,value=T)

if (groups == "YES") {   
   groupFile = read.delim("groups.tab",header=F,stringsAsFactors = F)
   groupFile=groupFile[groupFile$V2 %in% stringr::str_split_fixed(contrasts,pattern = "-",n = Inf)[1,],]
   #groupFile = groupFile[groupFile$V2 == strsplit(contrasts,"-")[[1]][1] | groupFile$V2 == strsplit(contrasts,"-")[[1]][2] ,] 
   
   splitFiles = gsub(".rds","",file.names)#str_split_fixed(file.names,pattern = "[.rd]",n = 2) 
   file.names=file.names[match(groupFile$V1,splitFiles,nomatch = F)]
   print(groupFile$V1)
   print(splitFiles)
   print(file.names)
}

readObj = list()
for (obj in file.names) {
    Name=strsplit(obj,".rds")[[1]][1]
    assign(paste0("S_",Name),readRDS(paste0(matrix,"/",obj)))
    readObj = append(readObj,paste0("S_",Name))  
 }

#for (obj in readObj) {
 # print(obj)   
  #sample = CreateSeuratObject(GetAssayData(object = eval(parse(text =obj)),slot = "counts")[,colnames(x = eval(parse(text =obj)))])
  #sample@assays$RNA@data = GetAssayData(object = eval(parse(text =obj)),slot = "data")[,colnames(x = eval(parse(text =obj)))]
  #sample@meta.data =eval(parse(text =obj))@meta.data
  #assign(obj,sample)

#}


combinedObj.list=list()
i=1
for (p in readObj){
    combinedObj.list[[p]] <- eval(parse(text = readObj[[i]]))
    i <- i + 1
 }


reference.list <- combinedObj.list[unlist(readObj)]
print(reference.list)
for (i in 1:length(x = reference.list)) {
#    reference.list[[i]] <- NormalizeData(object = reference.list[[i]], verbose = FALSE)
     reference.list[[i]] <- FindVariableFeatures(object = reference.list[[i]], selection.method = "vst", nfeatures = nAnchors, verbose = FALSE)
}

print(length(reference.list))
print(reference.list)
#combinedObj.anchors <- FindIntegrationAnchors(object.list = reference.list, dims = 1:30,anchor.features = nAnchors)
#combinedObj.integrated <- IntegrateData(anchorset = combinedObj.anchors, dims = 1:30)
#UPDATE VIA SEURAT VIGNETTE
reference.features <- SelectIntegrationFeatures(object.list = reference.list, nfeatures = 3000)
reference.list <- PrepSCTIntegration(object.list = reference.list, anchor.features = reference.features)
reference.anchors=FindIntegrationAnchors(object.list = reference.list, normalization.method = "SCT",anchor.features = reference.features)
combinedObj.integrated=IntegrateData(anchorset = reference.anchors, normalization.method = "SCT")

#Recover SingleR Annotations and Statistics
singleRList=list()
for (i in 1:length(reference.list)){
  obj=reference.list[[names(reference.list)[i]]]
  sample=gsub("^S_","",names(reference.list)[i])
  idTag=gsub(".*_","",names(which(combinedObj.integrated$Sample==sample))[1])
  singleR=obj@misc$SingleR
  for (j in 1:length(singleR)){
    if(names(singleR)[j]%in%names(singleRList)){
      indivSingleR=singleR[[j]]
      rownames(indivSingleR)=paste(rownames(indivSingleR),idTag,sep="_")
      indivSingleR=indivSingleR[intersect(rownames(indivSingleR),colnames(combinedObj.integrated)),]
      singleRList[[names(singleR)[j]]]=rbind(singleRList[[names(singleR)[j]]],indivSingleR)
    }else{
      indivSingleR=singleR[[j]]
      rownames(indivSingleR)=paste(rownames(indivSingleR),idTag,sep="_")
      indivSingleR=indivSingleR[intersect(rownames(indivSingleR),colnames(combinedObj.integrated)),]
      singleRList[[names(singleR)[j]]]=indivSingleR
    }
  }
}
combinedObj.integrated@misc$SingleR=singleRList

DefaultAssay(object = combinedObj.integrated) <- "integrated"
#combinedObj.integrated <- ScaleData(object = combinedObj.integrated, verbose = FALSE) #DO NOT SCALE AFTER INTEGRATION, PER SEURAT VIGNETTE

combinedObj.integratedRNA = combinedObj.integrated
DefaultAssay(object = combinedObj.integratedRNA) <- "SCT"

combinedObj.integratedRNA = FindVariableFeatures(combinedObj.integratedRNA,mean.cutoff = c(0.0125, 3),dispersion.cutoff = c(0.5, Inf),selection.method = "vst")
combinedObj.integratedRNA <- ScaleData(object = combinedObj.integratedRNA, verbose = FALSE)

if(ncol(combinedObj.integratedRNA)<50000){
#	mat1 <- t(as.matrix(FetchData(object = combinedObj.integratedRNA,slot = "counts",vars = rownames(combinedObj.integratedRNA))))
	mat1 <- as.matrix(combinedObj.integratedRNA@assays$SCT@counts) #BUG FIX - NW_20200501
	urdObj <- createURD(count.data = mat1, min.cells=3, min.counts=3)
	varGenes_batch = VariableFeatures(combinedObj.integrated)[VariableFeatures(combinedObj.integrated) %in% rownames(urdObj@logupx.data)]
	varGenes_merge = VariableFeatures(combinedObj.integratedRNA)[VariableFeatures(combinedObj.integratedRNA) %in% rownames(urdObj@logupx.data)]
	
	pcs_batch <- calcPCA(urdObj, pcs.store = 50,genes.use=varGenes_batch,mp.factor = 1.2)
	npcs_batch =  sum(pcs_batch@pca.sig)
	print(npcs_batch)
	
	pcs_merge <- calcPCA(urdObj, pcs.store = 50,genes.use=varGenes_merge,mp.factor = 1.2)
	npcs_merge =  sum(pcs_merge@pca.sig)
	print(npcs_merge)
}else{
	npcs_batch=50
	npcs_merge=50
	print(npcs_batch)
	print(npcs_merge)
}

runInt = function(obj,res,npcs){
       if (citeseq=="Yes"){
       	  obj = NormalizeData(obj,assay="CITESeq",normalization.method="CLR")
	      obj = ScaleData(obj,assay="CITESeq")
	      }
	      obj <- RunPCA(object = obj, npcs = 50, verbose = FALSE)
	      obj <- FindNeighbors(obj,dims = 1:npcs)
	      for (i in 1:length(res)){
	      	  obj <- FindClusters(obj, reduction = "pca", dims = 1:npcs, save.SNN = T,resolution = res[i],algorithm = clusterAlg)
		  }
		  obj <- RunUMAP(object = obj, reduction = "pca",dims = 1:npcs,n.components = 3)
    if (groups=="YES"){obj$groups = groupFile$V2[match(obj$Sample,  groupFile$V1,nomatch = F)]}
		  
		  runSingleR = function(obj,refFile,fineORmain){ #SingleR function call as implemented below
		  	     avg = AverageExpression(obj,assays = "SCT")
			     	 avg = as.data.frame(avg)
				     ref = refFile
				     	 s = SingleR(test = as.matrix(avg),ref = ref,labels = ref[[fineORmain]])
					   
						clustAnnot = s$labels
							   names(clustAnnot) = colnames(avg)
							   		     names(clustAnnot) = gsub("SCT.","",names(clustAnnot))
									     		       
												obj$clustAnnot = clustAnnot[match(obj$seurat_clusters,names(clustAnnot))]
													       return(obj$clustAnnot)
													       }

													       if(annotDB == "HPCA"){
													       		  obj$clustAnnot <- runSingleR(obj,HumanPrimaryCellAtlasData(),"label.main")
															  		 obj$clustAnnotDetail <-  runSingleR(obj,HumanPrimaryCellAtlasData(),"label.fine")
																	 }
																	 if(annotDB == "BP_encode"){
																	 	    obj$clustAnnot <-  runSingleR(obj,BlueprintEncodeData(),"label.main")
																		    		   obj$clustAnnotDetail <-  runSingleR(obj,BlueprintEncodeData(),"label.fine")
																				   }
																				   if(annotDB == "monaco"){
																				   	      obj$clustAnnot <-  runSingleR(obj,MonacoImmuneData(),"label.main")
																					      		     obj$clustAnnotDetail <-     runSingleR(obj,MonacoImmuneData(),"label.fine")
																							     }
																							     if(annotDB == "immu_cell_exp"){
																							     		obj$clustAnnot <-  runSingleR(obj,DatabaseImmuneCellExpressionData(),"label.main")
																										       obj$clustAnnotDetail <- runSingleR(obj,DatabaseImmuneCellExpressionData(),"label.fine")
																										       }
																										       
																										       if(annotDB == "immgen"){
																										       		  obj$clustAnnot <-  runSingleR(obj,ImmGenData(),"label.main")
																												  		 obj$clustAnnotDetail <- runSingleR(obj,ImmGenData(),"label.fine")
																														 }
																														 if(annotDB == "mouseRNAseq"){
																														 	    obj$clustAnnot <-  runSingleR(obj,MouseRNAseqData(),"label.main")
																															    		   obj$clustAnnotDetail <- runSingleR(obj,MouseRNAseqData(),"label.fine")
																																	   }
																																	   return(obj)
}

combinedObj.integrated=runInt(combinedObj.integrated,resolution,npcs_batch)
saveRDS(combinedObj.integrated,outDirSeurat)


combinedObj.integratedRNA = runInt(combinedObj.integratedRNA,resolution,npcs_merge)
saveRDS(combinedObj.integratedRNA,outDirMerge)


#IMAGE OUTPUT
### Sample output


pdf(paste0(outImageDir,"/merged_sample.pdf"))
DimPlot(combinedObj.integratedRNA,group.by="Sample")
dev.off()

pdf(paste0(outImageDir,"/integrated_sample.pdf"))
DimPlot(combinedObj.integrated,group.by="Sample")
dev.off()

### Clusters and silhouettes
for (res in resolutionString){
	pdf(paste0(outImageDir,"/clusterResolution_",res,"_merged.pdf"))
	resMod=as.numeric(gsub("\\.0$","",res))
	clusterPlot=DimPlot(combinedObj.integratedRNA,group.by=paste0("SCT_snn_res.",resMod),label=T,repel=T)
	print(clusterPlot + labs(title = paste0("Merged Samples at resolution ",res)))
	dev.off()
	
 pdf(paste0(outImageDir,"/clusterResolution_",res,"_integrated.pdf"))
	resMod=as.numeric(gsub("\\.0$","",res))
	clusterPlot=DimPlot(combinedObj.integrated,group.by=paste0("SCT_snn_res.",resMod),label=T,repel=T)
	print(clusterPlot + labs(title = paste0("Integrated Samples at resolution ",res)))
	dev.off()
 
 
	pdf(paste0(outImageDir,"/silhouetteResolution_",res,"_merged.pdf"))

	Idents(combinedObj.integratedRNA)=paste0("SCT_snn_res.",resMod)
	coord=Embeddings(combinedObj.integratedRNA,reduction='pca')[,1:30]
	clusters=Idents(combinedObj.integratedRNA)
	d = dist(coord,method="euclidean")
	sil=silhouette(as.numeric(as.character(clusters)),dist=d)
	palette=alpha(colour=hue_pal()(length(unique(Idents(combinedObj.integratedRNA)))),alpha=0.7)
	print(plot(sil, col=palette[as.factor(clusters[order(clusters,decreasing=F)])],
	main=paste0("Silhouette plot of clustering resolution ", res), lty=2,
	sub=paste("Average silhouette width:",format(round(mean(sil[,3]), 4), nsmall = 4))))
  
	abline(v=mean(sil[,3]), col="red4", lty=2)
	dev.off()

 pdf(paste0(outImageDir,"/silhouetteResolution_",res,"_integrated.pdf"))

	Idents(combinedObj.integrated)=paste0("SCT_snn_res.",resMod)
	coord=Embeddings(combinedObj.integrated,reduction='pca')[,1:30]
	clusters=Idents(combinedObj.integrated)
	d = dist(coord,method="euclidean")
	sil=silhouette(as.numeric(as.character(clusters)),dist=d)
	palette=alpha(colour=hue_pal()(length(unique(Idents(combinedObj.integrated)))),alpha=0.7)
	print(plot(sil, col=palette[as.factor(clusters[order(clusters,decreasing=F)])],
	main=paste0("Silhouette plot of clustering resolution ", res), lty=2,
	sub=paste("Average silhouette width:",format(round(mean(sil[,3]), 4), nsmall = 4))))
  
	abline(v=mean(sil[,3]), col="red4", lty=2)
	dev.off()
}

###

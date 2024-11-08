codeunit 80000 DC_Tracking_Mgt
{
    //This codeunit covert to ways of create document that have items with tracking:
    // - Invoices without match coming from COMPRAS (PURCHASES) --> OnAfterCreateWithoutMatchModifyPurchLine in CU CDC Purch. - Register
    // - Receipts and purch. order coming from PEDCOMPRA (PURCHORDERS)
    // - For the last one, there are 2 possibilities:
    //  - 1. Receipts: disable standard controls and create/modify reservation entry --> es_OnBeforeCheckMatchToWithTrack
    //  - Added event to avoid bug i archieved purch. order
    //  - 2. Purchase Order: same funtionality as purch. invoices
    //DUDA: Si me suscribo al OnAfterTransferPurchLine me vale para las acciones del paso 1 tanto en pedidos como en albaranes --> No tengo en nº de linea ,no me vale

    trigger OnRun()
    begin

    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"CDC Match Tracking Mgt.", 'OnBeforeTransferMatchTracking', '', false, false)]
    local procedure es_CreateTrackInfoOnBeforeTransferMatchTracking(ToPurchLine: Record "Purchase Line"; PurchDocMatch: Record "CDC Purch. Doc. Match"; DeleteExistingTracking: Boolean; UpdateExistingTracking: Boolean; var IsHandled: Boolean)
    var
        rlCDCTemplate: Record "CDC Template";
        clCaptureMgt: Codeunit "CDC Capture Management";
        vlLotNo: Code[20];
        vlSerie: Code[20];
        dlExpirationDate: Date;
        rlCDCDocument: Record "CDC Document";
        rlReservationEntry: Record "Reservation Entry";
    begin
        IF rlCDCDocument.GET(PurchDocMatch."Document No.") then begin
            If fRetreiveTrackValuesFromDoc(rlCDCDocument, PurchDocMatch."Document Line No.", vlLotNo, vlSerie, dlExpirationDate) then begin
                If NOT fExistReservationEntry(ToPurchLine, rlReservationEntry) then begin
                    fCreateReservationEntry(ToPurchLine, vlLotNo, vlSerie, dlExpirationDate);
                    IsHandled := true;
                end;
            end;
        end;
    end;


    [EventSubscriber(ObjectType::Codeunit, Codeunit::"CDC Purchase Order - Register", 'OnAfterCreateWithoutMatchModifyPurchLine', '', false, false)]
    local procedure es_CreateTrackInfoOnAfterCreateWithoutMatchModifyPurchLine(Document: Record "CDC Document"; var PurchLine: Record "Purchase Line"; DocumentLineNo: Integer)
    var
        rlCDCTemplate: Record "CDC Template";
        clCaptureMgt: Codeunit "CDC Capture Management";
        vlLotNo: Code[20];
        vlSerie: Code[20];
        dlExpirationDate: Date;
    begin
        If not (PurchLine.Type = PurchLine.Type::Item) then
            exit;
        If fRetreiveTrackValuesFromDoc(Document, DocumentLineNo, vlLotNo, vlSerie, dlExpirationDate) then
            fCreateReservationEntry(PurchLine, vlLotNo, vlSerie, dlExpirationDate);
    end;


    [EventSubscriber(ObjectType::Codeunit, Codeunit::"CDC Purch. Doc. - Management", 'OnBeforeCheckMatchToWithTrack', '', false, false)]
    local procedure es_OnBeforeCheckMatchToWithTrack(PurchOrderLine: Record "Purchase Line"; MatchedToDocType: Option; ShowError: Boolean; var Handled: Boolean; var ReturnValue: Boolean)
    var
        rlItem: Record Item;
    begin
        rlItem.GET(PurchOrderLine."No.");
        If (rlItem."Item Tracking Code" <> '') OR (rlItem."Lot Nos." <> '') then begin
            Handled := true;
            ReturnValue := true;
        end;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"CDC Purchase Order - Register", 'OnBeforeArchivePurchHeader', '', false, false)]
    local procedure es_OnBeforeArchivePurchHeader(PurchaseHeader: Record "Purchase Header"; var SuspendArchive: Boolean)
    begin
        //Activated due to an error in spanish translations. Solved in next versions
        fArchivePurcOrder(PurchaseHeader);
        SuspendArchive := true;
    end;

    local procedure fRetreiveTrackValuesFromDoc(pDocument: Record "CDC Document"; pDocumentLineNo: Integer; var pNoLot: Code[20]; var pNoSerie: Code[20]; var pExpirationDate: Date): Boolean
    var
        rlCDCTemplate: Record "CDC Template";
        clCaptureMgt: Codeunit "CDC Capture Management";

    begin
        //Add condition to avoid blank values
        Clear(clCaptureMgt);
        If rlCDCTemplate.Get(pDocument."Template No.") then begin
            pNoLot := clCaptureMgt.GetText(pDocument, 1, 'NUMLOTE', pDocumentLineNo);
            pNoSerie := clCaptureMgt.GetText(pDocument, 1, 'NUMSERIE', pDocumentLineNo);
            pExpirationDate := clCaptureMgt.GetDate(pDocument, 1, 'FECHACADUCIDAD', pDocumentLineNo)
        end;

        If (pNoLot <> '') OR (pNoSerie <> '') OR (pExpirationDate <> 0D) then
            exit(true)
        else
            exit(false);
    end;

    local procedure fCreateReservationEntry(pPurchaseLine: Record "Purchase Line"; pNoLot: Code[20]; pNoSerie: Code[20]; pExpirationDate: Date)
    var
        rlItem: Record Item;
        rlReserEntry: Record "Reservation Entry";
        clNoSeriesBatch: Codeunit "No. Series - Batch";
        vlNextEntryNo: Integer;

    begin
        if not rlItem.Get(pPurchaseLine."No.") then
            exit;
        rlItem.TestField("Item Tracking Code");
        rlItem.TestField("Lot Nos.");

        If rlReserEntry.FindLast() then
            vlNextEntryNo := rlReserEntry."Entry No." + 1
        else
            vlNextEntryNo := 1;
        Clear(rlReserEntry);
        rlReserEntry.Init();
        rlReserEntry."Entry No." := vlNextEntryNo;
        rlReserEntry."Item No." := pPurchaseLine."No.";
        rlReserEntry.Description := pPurchaseLine.Description;
        rlReserEntry."Location Code" := pPurchaseLine."Location Code";
        rlReserEntry."Variant Code" := pPurchaseLine."Variant Code";
        rlReserEntry.Validate("Quantity (Base)", pPurchaseLine."Qty. to Receive (Base)");
        rlReserEntry."Reservation Status" := rlReserEntry."Reservation Status"::Prospect;
        rlReserEntry."Source Type" := Database::"Purchase Line";
        rlReserEntry."Source ID" := pPurchaseLine."Document No.";
        If pPurchaseLine."Document Type" = pPurchaseLine."Document Type"::Invoice then
            rlReserEntry."Source Subtype" := rlReserEntry."Source Subtype"::"2"
        else
            rlReserEntry."Source Subtype" := rlReserEntry."Source Subtype"::"1";
        rlReserEntry."Source Ref. No." := pPurchaseLine."Line No.";
        rlReserEntry."Expected Receipt Date" := pPurchaseLine."Expected Receipt Date";
        rlReserEntry."Qty. per Unit of Measure" := pPurchaseLine."Qty. per Unit of Measure";
        If pNoSerie <> '' then
            rlReserEntry.Validate("Serial No.", pNoSerie);
        If pNoLot <> '' then
            rlReserEntry.Validate("Lot No.", pNoLot)
        else
            rlReserEntry.Validate("Lot No.", clNoSeriesBatch.GetNextNo(rlItem."Lot Nos.", WorkDate(), true));
        If pExpirationDate <> 0D then
            rlReserEntry.Validate("Expiration Date", pExpirationDate);
        rlReserEntry."Item Tracking" := rlReserEntry."Item Tracking"::"Lot No.";
        rlReserEntry."Created By" := UserId;
        rlReserEntry.Positive := true;
        rlReserEntry."Creation Date" := WorkDate();
        rlReserEntry.Insert();

        fCreateLotInfo(rlReserEntry);
    end;


    local procedure fCreateLotInfo(pReservationEntry: Record "Reservation Entry")
    var
        rlLotNoInfo: Record "Lot No. Information";
    begin
        rlLotNoInfo.Init();
        rlLotNoInfo."Item No." := pReservationEntry."Item No.";
        rlLotNoInfo."Variant Code" := pReservationEntry."Variant Code";
        rlLotNoInfo."Lot No." := pReservationEntry."Lot No.";
        rlLotNoInfo.Description := pReservationEntry.Description;
        rlLotNoInfo.Insert();
    end;

    local procedure fArchivePurcOrder(pPurchaseHeader: Record "Purchase Header")
    var
        ArchiveManagement: Codeunit ArchiveManagement;
        PurchCommentLineArchive: Record "Purch. Comment Line Archive";
        PurchHeaderArchive: Record "Purchase Header Archive";
        NextLineNo: Integer;
        ArchCommentDoc: Label 'Archived version created from Document: %1';
    begin
        ArchiveManagement.ArchPurchDocumentNoConfirm(pPurchaseHeader);
        PurchHeaderArchive.SETRANGE("Document Type", pPurchaseHeader."Document Type");
        PurchHeaderArchive.SETRANGE("No.", pPurchaseHeader."No.");
        IF NOT PurchHeaderArchive.FINDLAST THEN
            EXIT;

        PurchCommentLineArchive.SETRANGE("Document Type", PurchHeaderArchive."Document Type");
        PurchCommentLineArchive.SETRANGE("No.", PurchHeaderArchive."No.");
        PurchCommentLineArchive.SETRANGE("Doc. No. Occurrence", PurchHeaderArchive."Doc. No. Occurrence");
        PurchCommentLineArchive.SETRANGE("Version No.", PurchHeaderArchive."Version No.");
        IF PurchCommentLineArchive.FINDLAST THEN
            NextLineNo := PurchCommentLineArchive."Line No." + 10000
        ELSE
            NextLineNo := 10000;

        PurchCommentLineArchive."Document Type" := PurchHeaderArchive."Document Type";
        PurchCommentLineArchive."No." := PurchHeaderArchive."No.";
        PurchCommentLineArchive."Doc. No. Occurrence" := PurchHeaderArchive."Doc. No. Occurrence";
        PurchCommentLineArchive."Version No." := PurchHeaderArchive."Version No.";
        PurchCommentLineArchive."Line No." := NextLineNo;
        PurchCommentLineArchive.Date := TODAY;

        // IF GetVendorOrderNoValue(Document, 0) = '' THEN
        //     PurchCommentLineArchive.Comment := STRSUBSTNO(ArchCommentDoc, Document."No.")
        // ELSE
        //     PurchCommentLineArchive.Comment := STRSUBSTNO(ArchCommentDoc, Document."No.") + ', ' + STRSUBSTNO(ArchCommentVendor, GetVendorOrderNoValue(Document, 0));
        PurchCommentLineArchive.Comment := STRSUBSTNO(ArchCommentDoc, pPurchaseHeader."No.");
        PurchCommentLineArchive.INSERT;
    end;

    local procedure fExistReservationEntry(PurchLine: Record "Purchase Line"; var ReservationEntry: Record "Reservation Entry"): Boolean
    begin
        ReservationEntry.SETRANGE("Source Type", DATABASE::"Purchase Line");
        ReservationEntry.SETRANGE("Source Subtype", PurchLine."Document Type");
        ReservationEntry.SETRANGE("Source ID", PurchLine."Document No.");
        ReservationEntry.SETRANGE("Source Ref. No.", PurchLine."Line No.");
        ReservationEntry.SETRANGE("Reservation Status", ReservationEntry."Reservation Status"::Surplus, ReservationEntry."Reservation Status"::Prospect);
        If ReservationEntry.FindFirst() then
            exit(true)
        else
            exit(false);
    end;

    var
        myInt: Integer;
}